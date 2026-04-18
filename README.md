# SIEtoHDF5

A command-line tool that converts [SIE](https://github.com/efollman/libsie-zig) (Structural Impact Engineering) data files into [HDF5](https://www.hdfgroup.org/solutions/hdf5/) format. Written in Zig, it compiles HDF5 2.1.1 from C source as a static library, producing a fully self-contained binary with no runtime dependency on an installed HDF5 library.

## Building

```bash
# Native build
zig build

# Run
zig build run -- input.sie output.h5

# Run tests
zig build test --summary all

# Cross-compile for all supported platforms
zig build cross
```

## Usage

```
sie2hdf5 <input.sie> <output.h5>
```

The tool reads a `.sie` file and produces an HDF5 file with the following hierarchy:

```
/                           (root — file-level tags as attributes)
├── <test_name>/            (one group per test — test tags as attributes)
│   ├── <channel_name>/     (one group per channel — channel tags as attributes)
│   │   ├── dim0            (chunked f64 dataset — dimension 0 data)
│   │   ├── dim1            (chunked f64 dataset — dimension 1 data)
│   │   └── ...
│   └── ...
└── ...
```

- **Tags** from the SIE file are stored as HDF5 string attributes on the corresponding group or dataset.
- **Dimension data** (float64 time-history values) are stored in extensible chunked 1-D datasets with a chunk size of 4096 rows.

## Dependencies

| Dependency | Source | Purpose |
|---|---|---|
| **HDF5 2.1.1** | [HDFGroup/hdf5 tarball](https://github.com/HDFGroup/hdf5/archive/refs/tags/2.1.1.tar.gz) | Hierarchical data format library (compiled from C source) |
| **libsie-zig** | [efollman/libsie-zig](https://github.com/efollman/libsie-zig) (git, commit `331f2dc`) | SIE file parser providing `SieFile`, `Channel`, `Test`, `Dimension`, `Tag` types |

Both dependencies are declared in `build.zig.zon` and fetched automatically by the Zig build system. No system-installed libraries are required beyond Zig itself.

## Cross-Compilation

The build system supports cross-compilation for five targets from any host with Zig installed — no separate toolchains or sysroots are required:

| Target | Output Path |
|---|---|
| `x86_64-linux` | `zig-out/linux-x86_64/sie2hdf5` |
| `aarch64-linux` | `zig-out/linux-aarch64/sie2hdf5` |
| `x86_64-windows` | `zig-out/windows-x86_64/sie2hdf5.exe` |
| `x86_64-macos` | `zig-out/macos-x86_64/sie2hdf5` |
| `aarch64-macos` | `zig-out/macos-aarch64/sie2hdf5` |

## Project Structure

```
SIEtoHDF5/
├── build.zig                 Build system configuration
├── build.zig.zon             Package manifest and dependencies
├── hdf5_config/              Custom HDF5 build configuration
│   ├── H5pubconf.h           Cross-platform config header (replaces CMake-generated)
│   └── H5build_settings.c    Stub for H5build_settings[] symbol
├── src/
│   ├── main.zig              CLI entry point
│   ├── root.zig              Core conversion logic (two-pass pipeline)
│   └── hdf5.zig              Zig bindings for the HDF5 C API (manual extern declarations)
├── test/
│   └── data/                 SIE test files
└── docs/
    ├── ARCHITECTURE.md       Module responsibilities and data flow
    ├── HDF5_BUILD.md         How HDF5 is compiled from source and statically linked
    └── CROSS_COMPILATION.md  Supported targets and platform-specific details
```

## How HDF5 Is Built

Rather than linking against a system-installed `libhdf5`, the build system compiles ~291 HDF5 C source files directly using Zig's built-in C compiler (clang-based) and produces a static library. A custom `hdf5_config/H5pubconf.h` provides cross-platform configuration with compile-time platform detection (`_WIN32`, `__APPLE__`, `__linux__`) so the same header works for all five targets without code generation.

Key build settings:
- **C standard**: C11 (`-std=c11`)
- **GNU extensions**: `-D_GNU_SOURCE` for POSIX functions (`pread`, `qsort_r`, `strtok_r`, etc.)
- **Static build**: `H5_BUILT_AS_STATIC_LIB` disables dllimport/dllexport on Windows
- **Disabled features**: MPI, threading, zlib, szip, and other optional HDF5 features

See [docs/HDF5_BUILD.md](docs/HDF5_BUILD.md) for full details.

## Requirements

- Zig 0.15.2+

## License

TBD
