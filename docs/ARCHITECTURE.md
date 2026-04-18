# Architecture

This document describes the project structure, module responsibilities, and data flow of SIEtoHDF5.

## Project Structure

```
SIEtoHDF5/
├── build.zig                 # Build system configuration
├── build.zig.zon             # Package manifest and dependencies
├── docs/                     # Documentation
│   ├── ARCHITECTURE.md       # This file
│   ├── HDF5_BUILD.md
│   └── CROSS_COMPILATION.md
├── hdf5_config/              # Custom HDF5 build configuration
│   ├── H5pubconf.h           # Cross-platform config header (replaces CMake-generated)
│   └── H5build_settings.c    # Stub for H5build_settings[] symbol
├── src/
│   ├── main.zig              # CLI entry point
│   ├── root.zig              # Core conversion logic (library module)
│   └── hdf5.zig              # Zig bindings for the HDF5 C API
└── test/
    └── data/                 # Test SIE files
```

## Modules

### `src/main.zig` — CLI Entry Point

Minimal executable that:
1. Parses command-line arguments (`<input.sie> <output.h5>`)
2. Calls `SIEtoHDF5.convert(allocator, input, output)`
3. Reports errors to stderr

Uses a `GeneralPurposeAllocator` for all heap allocations.

### `src/root.zig` — Conversion Pipeline

The core library module exported as `SIEtoHDF5`. Implements a **two-pass conversion**:

**Pass 1 — Structure Pass:**
1. Opens the SIE file via `libsie`
2. Creates the HDF5 output file
3. Writes file-level tags as root attributes
4. Iterates over tests → channels → dimensions
5. Creates HDF5 groups (tests, channels) with tag attributes
6. Creates chunked datasets for each dimension
7. Builds a `ChannelEntry` list mapping channels to their datasets

**Pass 2 — Data Pass:**
1. Re-iterates over tests → channels
2. Attaches a spigot to each channel (streaming data reader)
3. Reads output blocks and appends float64 data to the corresponding datasets

#### Key Types

- **`ChannelEntry`** — Tracks the list of `ChunkedDataset` handles for a single channel's dimensions
- **`ConvertError`** — Union of `hdf5.Error` and `SieOpenFailed` / `OutOfMemory`

#### Helper Functions

- `groupName()` — Generates a sanitized null-terminated name for HDF5 groups (replaces `/` and null bytes with `_`)
- `writeTags()` — Writes all string tags as HDF5 string attributes on a group or dataset
- `sanitize()` — Replaces characters illegal in HDF5 names

### `src/hdf5.zig` — HDF5 C Bindings

Provides Zig-idiomatic wrappers around the HDF5 C API via `extern` declarations. Does **not** use `@cImport` — all function signatures are declared manually for build reliability across platforms.

#### Types

- **`File`** — HDF5 file handle (`H5Fcreate` / `H5Fclose`)
- **`Group`** — HDF5 group handle (`H5Gcreate2` / `H5Gclose`)
- **`ChunkedDataset`** — Extensible 1-D float64 dataset with chunked storage
  - `create()` — Creates with initial size 0, unlimited max, chunk size of 4096
  - `appendRows()` — Extends the dataset and writes new data via hyperslab selection

#### Constants

| Constant | Value | Purpose |
|---|---|---|
| `H5P_DEFAULT` | 0 | Default property list |
| `H5F_ACC_TRUNC` | 0x0002 | Truncate file on create |
| `H5S_UNLIMITED` | `maxInt(u64)` | Unlimited dimension size |
| `H5T_VARIABLE` | `maxInt(usize)` | Variable-length string type |
| `CHUNK_ROWS` | 4096 | Chunk size for datasets |

#### Initialization

`hdf5.init()` calls `H5open()` once to initialize the HDF5 library. This must happen before accessing extern globals like `H5T_NATIVE_DOUBLE_g`. The `File.create()` method calls `init()` automatically.

## Data Flow

```
┌─────────────┐      libsie       ┌──────────────┐
│  .sie file  │ ──────────────── │  SieFile      │
└─────────────┘                   │  ├─ Tests[]   │
                                  │  │  ├─ Channels[]
                                  │  │  │  ├─ Dimensions[]
                                  │  │  │  └─ Tags[]
                                  │  │  └─ Tags[]
                                  │  └─ FileTags[] │
                                  └──────┬─────────┘
                                         │
                              root.zig convert()
                                         │
                          ┌──────────────┴──────────────┐
                          │  Structure Pass              │
                          │  (groups, datasets, attrs)   │
                          └──────────────┬──────────────┘
                                         │
                          ┌──────────────┴──────────────┐
                          │  Data Pass                   │
                          │  (spigot → appendRows)       │
                          └──────────────┬──────────────┘
                                         │
                                    hdf5.zig
                                         │
                                  ┌──────┴──────┐
                                  │  .h5 file   │
                                  └─────────────┘
```

## Build System

The `build.zig` defines four steps:

| Step | Command | Description |
|---|---|---|
| `install` (default) | `zig build` | Builds the native executable |
| `run` | `zig build run -- <args>` | Builds and runs with arguments |
| `test` | `zig build test` | Runs library and executable tests |
| `cross` | `zig build cross` | Cross-compiles for all 5 targets |

### Module Dependency Graph

```
main.zig
├── imports: SIEtoHDF5 (root.zig)
│   ├── imports: libsie (libsie-zig/src/root.zig)
│   └── @import("hdf5.zig")
│       └── links: libhdf5.a (static, from C source)
└── imports: libsie
```

All modules that use HDF5 extern declarations (directly or transitively) have `link_libc = true`.

## Tests

Two test modules are configured:

1. **Library tests** (`src/root.zig`) — Tests the conversion pipeline with a sample SIE file
2. **Executable tests** (`src/main.zig`) — Smoke test verifying compilation

Run with:
```bash
zig build test --summary all
```
