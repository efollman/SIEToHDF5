# Cross-Compilation

SIEtoHDF5 supports cross-compilation for five target platforms from any host that has Zig 0.15.2 installed. The Zig build system handles all cross-compilation automatically — no separate toolchains or sysroots are required.

## Supported Targets

| Target | OS | Architecture | ABI |
|---|---|---|---|
| `x86_64-linux` | Linux | x86_64 | LP64 (gnu) |
| `aarch64-linux` | Linux | AArch64 | LP64 (gnu) |
| `x86_64-windows` | Windows | x86_64 | LLP64 (mingw) |
| `x86_64-macos` | macOS | x86_64 | LP64 |
| `aarch64-macos` | macOS | AArch64 | LP64 |

## Building

```bash
# Build all five targets at once
zig build cross

# Output binaries are placed in:
#   zig-out/linux-x86_64/sie2hdf5
#   zig-out/linux-aarch64/sie2hdf5
#   zig-out/windows-x86_64/sie2hdf5.exe
#   zig-out/macos-x86_64/sie2hdf5
#   zig-out/macos-aarch64/sie2hdf5
```

## How It Works

The `cross` build step in `build.zig` iterates over all five platform tuples:

```zig
const cross_step = b.step("cross", "Build for all supported platforms");
inline for (.{
    .{ .os = .linux,   .arch = .x86_64  },
    .{ .os = .linux,   .arch = .aarch64  },
    .{ .os = .windows, .arch = .x86_64  },
    .{ .os = .macos,   .arch = .x86_64  },
    .{ .os = .macos,   .arch = .aarch64  },
}) |platform| {
    const cross_target = b.resolveTargetQuery(.{
        .os_tag = platform.os,
        .cpu_arch = platform.arch,
    });
    // Build HDF5 and the executable for this target...
}
```

For each target, a separate HDF5 static library is compiled using the same `buildHdf5Lib()` function used for native builds. The Zig C compiler automatically provides the correct target headers and libc for each platform.

## Platform-Specific Details

### Linux (x86_64, aarch64)

- **ABI**: LP64 — `sizeof(long) = 8`, `sizeof(off_t) = 8`
- **libc**: Zig bundles musl/glibc headers for cross-compilation
- `-D_GNU_SOURCE` enables POSIX extensions (`pread`, `pwrite`, `qsort_r`, `strtok_r`, `clock_gettime`, `nanosleep`, etc.)
- `long double`: 16 bytes on both x86_64 and aarch64

### Windows (x86_64)

- **ABI**: LLP64 — `sizeof(long) = 4`, `sizeof(off_t) = 4`, `sizeof(size_t) = 8`
- **libc**: mingw-w64 (bundled with Zig)
- `H5_HAVE_WIN32_API`, `H5_HAVE_WINDOWS`, `H5_HAVE_MINGW` are defined in `H5pubconf.h`
- HDF5's `H5win32defs.h` remaps POSIX functions to Windows equivalents:
  - `dlopen` → `LoadLibrary`, `dlsym` → `GetProcAddress`, `dlclose` → `FreeLibrary`
  - `ftruncate` → `_chsize_s`
  - `qsort_r` → `HDqsort_context` (wraps `qsort_s`)
  - `strndup` → `H5_strndup` (internal)
  - `stat` / `fstat` → `_stati64` / `_fstati64`
- `H5_BUILT_AS_STATIC_LIB` disables `dllimport`/`dllexport` decorations
- `long double`: 8 bytes (same as `double` on Windows)

### macOS (x86_64, aarch64)

- **ABI**: LP64 — `sizeof(long) = 8`, `sizeof(off_t) = 8`
- `H5_HAVE_DARWIN` is defined for macOS-specific code paths
- `long double`: 16 bytes on x86_64, 8 bytes on aarch64 (ARM)
- Complex number types are available (unlike Windows)
- Zig provides macOS SDK headers for cross-compilation from Linux

## Configuration Header Portability

The single `hdf5_config/H5pubconf.h` file handles all five targets using preprocessor conditionals:

```
#if defined(_WIN32)      → Windows-specific settings
#elif defined(__APPLE__) → macOS-specific settings
#else                    → Linux settings (default)
```

Within each platform block, architecture-specific settings use:

```
#if defined(__x86_64__)  → x86_64-specific (e.g., long double size)
#elif defined(__aarch64__) → AArch64-specific
```

This approach avoids needing separate config files per target.

## Output Directory Structure

Cross-compiled binaries are installed to target-specific subdirectories:

```
zig-out/
├── linux-x86_64/
│   └── sie2hdf5
├── linux-aarch64/
│   └── sie2hdf5
├── windows-x86_64/
│   └── sie2hdf5.exe
├── macos-x86_64/
│   └── sie2hdf5
└── macos-aarch64/
    └── sie2hdf5
```

This is configured via the `dest_dir` override in `build.zig`:

```zig
const cross_install = b.addInstallArtifact(cross_exe, .{
    .dest_dir = .{ .override = .{
        .custom = @tagName(platform.os) ++ "-" ++ @tagName(platform.arch),
    }},
});
```
