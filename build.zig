const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Dependencies ---

    const libsie_dep = b.dependency("libsie", .{
        .target = target,
        .optimize = optimize,
    });
    const hdf5_dep = b.dependency("hdf5", .{});

    // libsie-zig uses createModule (not addModule), so we build the module
    // from its source directly.
    const libsie_mod = b.createModule(.{
        .root_source_file = libsie_dep.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- Library module ---

    const lib_mod = b.addModule("SIEtoHDF5", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("libsie", libsie_mod);
    lib_mod.link_libc = true;

    // --- Build HDF5 from source for native target ---

    const hdf5_native = buildHdf5Lib(b, hdf5_dep, target, optimize);

    // --- Executable ---

    const exe = b.addExecutable(.{
        .name = "sie2hdf5",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "SIEtoHDF5", .module = lib_mod },
                .{ .name = "libsie", .module = libsie_mod },
            },
        }),
    });
    exe.root_module.linkLibrary(hdf5_native);
    exe.root_module.link_libc = true;

    b.installArtifact(exe);

    // --- Run step ---

    const run_step = b.step("run", "Run the converter");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // --- Cross-compilation convenience targets ---

    const cross_step = b.step("cross", "Build for all supported platforms");
    inline for (.{
        .{ .os = .linux, .arch = .x86_64 },
        .{ .os = .linux, .arch = .aarch64 },
        .{ .os = .windows, .arch = .x86_64 },
        .{ .os = .macos, .arch = .x86_64 },
        .{ .os = .macos, .arch = .aarch64 },
    }) |platform| {
        const cross_target = b.resolveTargetQuery(.{
            .os_tag = platform.os,
            .cpu_arch = platform.arch,
        });
        const hdf5_cross = buildHdf5Lib(b, hdf5_dep, cross_target, optimize);
        const cross_exe = b.addExecutable(.{
            .name = "sie2hdf5",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = cross_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "SIEtoHDF5", .module = lib_mod },
                    .{ .name = "libsie", .module = libsie_mod },
                },
            }),
        });
        cross_exe.root_module.linkLibrary(hdf5_cross);
        cross_exe.root_module.link_libc = true;
        const cross_install = b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{ .override = .{ .custom = @tagName(platform.os) ++ "-" ++ @tagName(platform.arch) } },
        });
        cross_step.dependOn(&cross_install.step);
    }

    // --- Tests ---

    const test_step = b.step("test", "Run tests");

    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_test_mod.addImport("libsie", libsie_mod);
    lib_test_mod.linkLibrary(hdf5_native);
    lib_test_mod.link_libc = true;

    const lib_tests = b.addTest(.{ .root_module = lib_test_mod });
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    const exe_test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "SIEtoHDF5", .module = lib_mod },
            .{ .name = "libsie", .module = libsie_mod },
        },
    });
    exe_test_mod.linkLibrary(hdf5_native);
    exe_test_mod.link_libc = true;

    const exe_tests = b.addTest(.{ .root_module = exe_test_mod });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}

// ---------------------------------------------------------------------------
// Build HDF5 2.1.1 from C source as a static library for a given target.
// ---------------------------------------------------------------------------
fn buildHdf5Lib(
    b: *std.Build,
    hdf5_dep: *std.Build.Dependency,
    t: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const hdf5_lib = b.addLibrary(.{
        .name = "hdf5",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = t,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // All C source files from HDF5 src/ (from CMakeLists.txt common_SRCS)
    hdf5_lib.root_module.addCSourceFiles(.{
        .root = hdf5_dep.path("src"),
        .files = &hdf5_c_sources,
        .flags = &.{ "-std=c11", "-w", "-D_GNU_SOURCE" },
    });

    // Our generated build-settings stub
    hdf5_lib.root_module.addCSourceFile(.{
        .file = b.path("hdf5_config/H5build_settings.c"),
        .flags = &.{ "-std=c11", "-w", "-D_GNU_SOURCE" },
    });

    // Include paths: HDF5 source headers + our config directory
    hdf5_lib.root_module.addIncludePath(hdf5_dep.path("src"));
    hdf5_lib.root_module.addIncludePath(hdf5_dep.path("src/H5FDsubfiling"));
    hdf5_lib.root_module.addIncludePath(b.path("hdf5_config"));

    return hdf5_lib;
}

// ---------------------------------------------------------------------------
// Complete list of HDF5 2.1.1 C source files (from src/CMakeLists.txt).
// Files for disabled features (MPI, HDFS, S3, mirror, direct, subfiling,
// Windows-only, etc.) are included — they compile as empty translation units
// when the corresponding H5pubconf.h defines are absent.
// ---------------------------------------------------------------------------
const hdf5_c_sources = [_][]const u8{
    // H5 core
    "H5.c",
    "H5checksum.c",
    "H5dbg.c",
    "H5mpi.c",
    "H5system.c",
    "H5timer.c",
    "H5trace.c",
    // H5A — attributes
    "H5A.c",
    "H5Abtree2.c",
    "H5Adense.c",
    "H5Adeprec.c",
    "H5Aint.c",
    "H5Atest.c",
    // H5AC — metadata cache
    "H5AC.c",
    "H5ACdbg.c",
    "H5ACmpio.c",
    "H5ACproxy_entry.c",
    // H5B — B-trees
    "H5B.c",
    "H5Bcache.c",
    "H5Bdbg.c",
    // H5B2 — v2 B-trees
    "H5B2.c",
    "H5B2cache.c",
    "H5B2dbg.c",
    "H5B2hdr.c",
    "H5B2int.c",
    "H5B2internal.c",
    "H5B2leaf.c",
    "H5B2stat.c",
    "H5B2test.c",
    // H5C — cache
    "H5C.c",
    "H5Cdbg.c",
    "H5Centry.c",
    "H5Cepoch.c",
    "H5Cimage.c",
    "H5Cint.c",
    "H5Clog.c",
    "H5Clog_json.c",
    "H5Clog_trace.c",
    "H5Cmpio.c",
    "H5Cprefetched.c",
    "H5Cquery.c",
    "H5Ctag.c",
    "H5Ctest.c",
    // H5CX — context
    "H5CX.c",
    // H5D — datasets
    "H5D.c",
    "H5Dbtree.c",
    "H5Dbtree2.c",
    "H5Dchunk.c",
    "H5Dcompact.c",
    "H5Dcontig.c",
    "H5Ddbg.c",
    "H5Ddeprec.c",
    "H5Dearray.c",
    "H5Defl.c",
    "H5Dfarray.c",
    "H5Dfill.c",
    "H5Dint.c",
    "H5Dio.c",
    "H5Dlayout.c",
    "H5Dmpio.c",
    "H5Dnone.c",
    "H5Doh.c",
    "H5Dscatgath.c",
    "H5Dselect.c",
    "H5Dsingle.c",
    "H5Dtest.c",
    "H5Dvirtual.c",
    // H5E — errors
    "H5E.c",
    "H5Edeprec.c",
    "H5Eint.c",
    // H5EA — extensible arrays
    "H5EA.c",
    "H5EAcache.c",
    "H5EAdbg.c",
    "H5EAdblkpage.c",
    "H5EAdblock.c",
    "H5EAhdr.c",
    "H5EAiblock.c",
    "H5EAint.c",
    "H5EAsblock.c",
    "H5EAstat.c",
    "H5EAtest.c",
    // H5ES — event sets
    "H5ES.c",
    "H5ESevent.c",
    "H5ESint.c",
    "H5ESlist.c",
    // H5F — files
    "H5F.c",
    "H5Faccum.c",
    "H5Fcwfs.c",
    "H5Fdbg.c",
    "H5Fdeprec.c",
    "H5Fefc.c",
    "H5Ffake.c",
    "H5Fint.c",
    "H5Fio.c",
    "H5Fmount.c",
    "H5Fmpi.c",
    "H5Fquery.c",
    "H5Fsfile.c",
    "H5Fspace.c",
    "H5Fsuper.c",
    "H5Fsuper_cache.c",
    "H5Ftest.c",
    // H5FA — fixed arrays
    "H5FA.c",
    "H5FAcache.c",
    "H5FAdbg.c",
    "H5FAdblkpage.c",
    "H5FAdblock.c",
    "H5FAhdr.c",
    "H5FAint.c",
    "H5FAstat.c",
    "H5FAtest.c",
    // H5FD — file drivers
    "H5FD.c",
    "H5FDcore.c",
    "H5FDdirect.c",
    "H5FDfamily.c",
    "H5FDhdfs.c",
    "H5FDint.c",
    "H5FDlog.c",
    "H5FDmirror.c",
    "H5FDmpi.c",
    "H5FDmpio.c",
    "H5FDmulti.c",
    "H5FDmulti_int.c",
    "H5FDonion.c",
    "H5FDonion_header.c",
    "H5FDonion_history.c",
    "H5FDonion_index.c",
    "H5FDros3.c",
    "H5FDros3_s3comms.c",
    "H5FDsec2.c",
    "H5FDspace.c",
    "H5FDsplitter.c",
    "H5FDstdio.c",
    "H5FDstdio_int.c",
    "H5FDtest.c",
    "H5FDwindows.c",
    // H5FL — free lists
    "H5FL.c",
    // H5FO — open object info
    "H5FO.c",
    // H5FS — free space
    "H5FS.c",
    "H5FScache.c",
    "H5FSdbg.c",
    "H5FSint.c",
    "H5FSsection.c",
    "H5FSstat.c",
    "H5FStest.c",
    // H5G — groups
    "H5G.c",
    "H5Gbtree2.c",
    "H5Gcache.c",
    "H5Gcompact.c",
    "H5Gdense.c",
    "H5Gdeprec.c",
    "H5Gent.c",
    "H5Gint.c",
    "H5Glink.c",
    "H5Gloc.c",
    "H5Gname.c",
    "H5Gnode.c",
    "H5Gobj.c",
    "H5Goh.c",
    "H5Groot.c",
    "H5Gstab.c",
    "H5Gtest.c",
    "H5Gtraverse.c",
    // H5HF — fractal heap
    "H5HF.c",
    "H5HFbtree2.c",
    "H5HFcache.c",
    "H5HFdbg.c",
    "H5HFdblock.c",
    "H5HFdtable.c",
    "H5HFhdr.c",
    "H5HFhuge.c",
    "H5HFiblock.c",
    "H5HFiter.c",
    "H5HFman.c",
    "H5HFsection.c",
    "H5HFspace.c",
    "H5HFstat.c",
    "H5HFtest.c",
    "H5HFtiny.c",
    // H5HG — global heap
    "H5HG.c",
    "H5HGcache.c",
    "H5HGdbg.c",
    "H5HGquery.c",
    // H5HL — local heap
    "H5HL.c",
    "H5HLcache.c",
    "H5HLdbg.c",
    "H5HLdblk.c",
    "H5HLint.c",
    "H5HLprfx.c",
    // H5I — identifiers
    "H5I.c",
    "H5Idbg.c",
    "H5Ideprec.c",
    "H5Iint.c",
    "H5Itest.c",
    // H5L — links
    "H5L.c",
    "H5Ldeprec.c",
    "H5Lexternal.c",
    "H5Lint.c",
    // H5M — maps
    "H5M.c",
    // H5MF — file memory management
    "H5MF.c",
    "H5MFaggr.c",
    "H5MFdbg.c",
    "H5MFsection.c",
    // H5MM — memory management
    "H5MM.c",
    // H5O — object headers
    "H5O.c",
    "H5Oainfo.c",
    "H5Oalloc.c",
    "H5Oattr.c",
    "H5Oattribute.c",
    "H5Obogus.c",
    "H5Obtreek.c",
    "H5Ocache.c",
    "H5Ocache_image.c",
    "H5Ochunk.c",
    "H5Ocont.c",
    "H5Ocopy.c",
    "H5Ocopy_ref.c",
    "H5Odbg.c",
    "H5Odeleted.c",
    "H5Odeprec.c",
    "H5Odrvinfo.c",
    "H5Odtype.c",
    "H5Oefl.c",
    "H5Ofill.c",
    "H5Oflush.c",
    "H5Ofsinfo.c",
    "H5Oginfo.c",
    "H5Oint.c",
    "H5Olayout.c",
    "H5Olinfo.c",
    "H5Olink.c",
    "H5Omessage.c",
    "H5Omtime.c",
    "H5Oname.c",
    "H5Onull.c",
    "H5Opline.c",
    "H5Orefcount.c",
    "H5Osdspace.c",
    "H5Oshared.c",
    "H5Oshmesg.c",
    "H5Ostab.c",
    "H5Otest.c",
    "H5Ounknown.c",
    // H5P — property lists
    "H5P.c",
    "H5Pacpl.c",
    "H5Pdapl.c",
    "H5Pdcpl.c",
    "H5Pdeprec.c",
    "H5Pdxpl.c",
    "H5Pencdec.c",
    "H5Pfapl.c",
    "H5Pfcpl.c",
    "H5Pfmpl.c",
    "H5Pgcpl.c",
    "H5Pint.c",
    "H5Plapl.c",
    "H5Plcpl.c",
    "H5Pmapl.c",
    "H5Pmcpl.c",
    "H5Pocpl.c",
    "H5Pocpypl.c",
    "H5Pstrcpl.c",
    "H5Ptest.c",
    // H5PB — page buffering
    "H5PB.c",
    // H5PL — plugins
    "H5PL.c",
    "H5PLint.c",
    "H5PLpath.c",
    "H5PLplugin_cache.c",
    // H5R — references
    "H5R.c",
    "H5Rdeprec.c",
    "H5Rint.c",
    // H5RS — reference-counted strings
    "H5RS.c",
    // H5RT — reference tracking
    "H5RT.c",
    // H5S — dataspaces
    "H5S.c",
    "H5Sall.c",
    "H5Sdbg.c",
    "H5Sdeprec.c",
    "H5Shyper.c",
    "H5Smpio.c",
    "H5Snone.c",
    "H5Spoint.c",
    "H5Sselect.c",
    "H5Stest.c",
    // H5SL — skip lists
    "H5SL.c",
    // H5SM — shared messages
    "H5SM.c",
    "H5SMbtree2.c",
    "H5SMcache.c",
    "H5SMmessage.c",
    "H5SMtest.c",
    // H5T — datatypes
    "H5T.c",
    "H5Tarray.c",
    "H5Tbit.c",
    "H5Tcommit.c",
    "H5Tcomplex.c",
    "H5Tcompound.c",
    "H5Tconv.c",
    "H5Tconv_array.c",
    "H5Tconv_bitfield.c",
    "H5Tconv_complex.c",
    "H5Tconv_compound.c",
    "H5Tconv_enum.c",
    "H5Tconv_float.c",
    "H5Tconv_integer.c",
    "H5Tconv_reference.c",
    "H5Tconv_string.c",
    "H5Tconv_vlen.c",
    "H5Tcset.c",
    "H5Tdbg.c",
    "H5Tdeprec.c",
    "H5Tenum.c",
    "H5Tfields.c",
    "H5Tfixed.c",
    "H5Tfloat.c",
    "H5Tinit_float.c",
    "H5Tnative.c",
    "H5Toffset.c",
    "H5Toh.c",
    "H5Topaque.c",
    "H5Torder.c",
    "H5Tpad.c",
    "H5Tprecis.c",
    "H5Tref.c",
    "H5Tstrpad.c",
    "H5Tvisit.c",
    "H5Tvlen.c",
    // H5TS — threading stubs
    "H5TS.c",
    "H5TSatomic.c",
    "H5TSbarrier.c",
    "H5TSc11.c",
    "H5TScond.c",
    "H5TSint.c",
    "H5TSkey.c",
    "H5TSmutex.c",
    "H5TSonce.c",
    "H5TSpool.c",
    "H5TSpthread.c",
    "H5TSrec_rwlock.c",
    "H5TSrwlock.c",
    "H5TSsemaphore.c",
    "H5TSthread.c",
    "H5TSwin.c",
    // H5UC — reference counting
    "H5UC.c",
    // H5VL — virtual object layer
    "H5VL.c",
    "H5VLcallback.c",
    "H5VLdyn_ops.c",
    "H5VLint.c",
    "H5VLnative.c",
    "H5VLnative_attr.c",
    "H5VLnative_blob.c",
    "H5VLnative_dataset.c",
    "H5VLnative_datatype.c",
    "H5VLnative_file.c",
    "H5VLnative_group.c",
    "H5VLnative_link.c",
    "H5VLnative_introspect.c",
    "H5VLnative_object.c",
    "H5VLnative_token.c",
    "H5VLpassthru.c",
    "H5VLpassthru_int.c",
    "H5VLquery.c",
    "H5VLtest.c",
    // H5VM — vector/array math
    "H5VM.c",
    // H5WB — wrapped buffers
    "H5WB.c",
    // H5Z — filters
    "H5Z.c",
    "H5Zdeflate.c",
    "H5Zfletcher32.c",
    "H5Znbit.c",
    "H5Zscaleoffset.c",
    "H5Zshuffle.c",
    "H5Zszip.c",
    "H5Ztrans.c",
};
