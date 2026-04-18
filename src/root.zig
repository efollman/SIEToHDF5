const std = @import("std");
const libsie = @import("libsie");
const hdf5 = @import("hdf5.zig");

const SieFile = libsie.sie_file.SieFile;
const Tag = libsie.tag.Tag;
const OutputType = libsie.output.OutputType;

pub const ConvertError = hdf5.Error || error{
    SieOpenFailed,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Per-channel dataset tracking (maps structure pass → data pass)
// ---------------------------------------------------------------------------
const ChannelEntry = struct {
    dim_datasets: std.ArrayList(hdf5.ChunkedDataset),

    fn deinit(self: *ChannelEntry, allocator: std.mem.Allocator) void {
        for (self.dim_datasets.items) |ds| ds.close();
        self.dim_datasets.deinit(allocator);
    }
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn convert(allocator: std.mem.Allocator, input_path: [:0]const u8, output_path: [:0]const u8) !void {
    // Open SIE file
    var sf = try SieFile.open(allocator, input_path);
    defer sf.deinit();

    // Create HDF5 output
    const h5 = try hdf5.File.create(output_path);
    defer h5.close();

    // Collect per-channel datasets for the data pass
    var entries: std.ArrayList(ChannelEntry) = .empty;
    defer {
        for (entries.items) |*e| e.deinit(allocator);
        entries.deinit(allocator);
    }

    // ====================== Structure Pass =================================
    // File-level tags → root attributes
    try writeTags(allocator, h5.id, sf.getFileTags());

    const tests = sf.getTests();
    for (tests) |*test_obj| {
        // --- Test group ---
        const tname = try groupName(allocator, test_obj.getName(), test_obj.getId(), "test");
        defer allocator.free(tname);

        const test_grp = try h5.createGroup(tname);
        defer test_grp.close();

        try writeTags(allocator, test_grp.id, test_obj.getTags());

        // --- Channels in this test ---
        const channels = test_obj.getChannels();
        for (channels) |*ch| {
            const cname = try groupName(allocator, ch.getName(), ch.getId(), "ch");
            defer allocator.free(cname);

            const ch_grp = try test_grp.createGroup(cname);
            defer ch_grp.close();

            try writeTags(allocator, ch_grp.id, ch.getTags());

            // --- Dimensions → chunked datasets ---
            var entry = ChannelEntry{ .dim_datasets = .empty };

            const dims = ch.getDimensions();
            for (dims, 0..) |*dim, di| {
                var buf: [64]u8 = undefined;
                const dset_name = std.fmt.bufPrintZ(&buf, "dim{d}", .{di}) catch "dim";

                const ds = try hdf5.ChunkedDataset.create(ch_grp.id, dset_name, hdf5.CHUNK_ROWS);

                // Store dimension name and tags as dataset attributes
                const dim_name_z = try allocator.dupeZ(u8, dim.getName());
                defer allocator.free(dim_name_z);
                hdf5.writeStringAttr(ds.id, "name", dim_name_z) catch {};

                try writeTagsOnDataset(allocator, ds.id, dim.getTags());

                try entry.dim_datasets.append(allocator, ds);
            }

            try entries.append(allocator, entry);
        }
    }

    // ====================== Data Pass ======================================
    var ch_idx: usize = 0;
    const tests2 = sf.getTests();
    for (tests2) |*test_obj| {
        const channels = test_obj.getChannels();
        for (channels) |*ch| {
            defer ch_idx += 1;
            if (ch_idx >= entries.items.len) continue;
            const entry = &entries.items[ch_idx];

            var spig = sf.attachSpigot(ch) catch continue;
            defer spig.deinit();

            while (try spig.get()) |out| {
                for (0..out.num_dims) |d| {
                    if (d >= entry.dim_datasets.items.len) continue;
                    if (out.dimensions[d].dim_type == .Float64) {
                        if (out.dimensions[d].float64_data) |data| {
                            if (out.num_rows <= data.len) {
                                try entry.dim_datasets.items[d].appendRows(data[0..out.num_rows]);
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a sanitized null-terminated group name. Uses object name if non-empty,
/// otherwise falls back to "<prefix>_<id>".
fn groupName(allocator: std.mem.Allocator, name: []const u8, id: u32, prefix: []const u8) ![:0]u8 {
    if (name.len > 0) {
        return sanitize(allocator, name);
    }
    var buf: [80]u8 = undefined;
    const fallback = std.fmt.bufPrint(&buf, "{s}_{d}", .{ prefix, id }) catch prefix;
    return allocator.dupeZ(u8, fallback);
}

/// Replace '/' and null bytes (which are illegal in HDF5 names) with '_'.
fn sanitize(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const out = try allocator.allocSentinel(u8, s.len, 0);
    for (out[0..s.len], s) |*o, c| {
        o.* = if (c == '/' or c == 0) '_' else c;
    }
    return out;
}

/// Write all string tags as HDF5 attributes on the given object.
/// Binary tags are skipped. Duplicate/invalid names are silently ignored.
fn writeTags(allocator: std.mem.Allocator, loc_id: hdf5.hid_t, tags: []const Tag) !void {
    for (tags) |*t| {
        writeOneTag(allocator, loc_id, t) catch continue;
    }
}

/// Same as writeTags but explicitly for dataset objects (identical logic).
fn writeTagsOnDataset(allocator: std.mem.Allocator, loc_id: hdf5.hid_t, tags: []const Tag) !void {
    return writeTags(allocator, loc_id, tags);
}

fn writeOneTag(allocator: std.mem.Allocator, loc_id: hdf5.hid_t, t: *const Tag) !void {
    const key = t.getId();
    if (key.len == 0) return;

    const key_z = try allocator.dupeZ(u8, key);
    defer allocator.free(key_z);

    if (t.isString()) {
        const val = t.getString() orelse "";
        const val_z = try allocator.dupeZ(u8, val);
        defer allocator.free(val_z);
        try hdf5.writeStringAttr(loc_id, key_z, val_z);
    }
    // Binary tags are not written (no standard HDF5 representation)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
test "convert min timhis SIE to HDF5" {
    const allocator = std.testing.allocator;
    const out_path = "test_output.h5";

    convert(allocator, "test/data/sie_min_timhis_a_19EFAA61.sie", out_path) catch |err| {
        std.debug.print("convert failed: {}\n", .{err});
        return err;
    };
    defer std.fs.cwd().deleteFile(out_path) catch {};

    // Verify output file was created
    const stat = try std.fs.cwd().statFile(out_path);
    try std.testing.expect(stat.size > 0);
}
