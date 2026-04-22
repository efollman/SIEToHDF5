# ConvertSIE

[![CI](https://github.com/efollman/ConvertSIE/actions/workflows/ci.yml/badge.svg)](https://github.com/efollman/ConvertSIE/actions/workflows/ci.yml)

A command-line tool (and Windows GUI) that converts [SIE](https://github.com/efollman/libsie-zig) data files into multiple output formats. Written in Zig, it compiles HDF5 from C source as a static library, producing fully self-contained binaries with no runtime dependencies.

## Supported Output Formats

| Extension | Format | Description |
|---|---|---|
| `.h5` / `.hdf5` | HDF5 | Hierarchical data format with groups, datasets, and attributes |
| `.txt` | ASCII | Human-readable text with metadata tags and tab-separated channel data |
| `.csv` | CSV | Comma-separated values with channels as side-by-side tables |
| `.xlsx` | Excel | Excel 2007+ spreadsheet with the same layout as CSV |
| `.asc` | Vector-style ASCII | Vector CANalyzer-compatible log; filters to raw CAN channels only |
| `.csv` (with `--can-err`) | J1939 CAN Errors | DM1 active-DTC extraction from raw CAN channels, CSV output |

## Building

```bash
# Native build
zig build

# Run
zig build run -- input.sie output.csv

# Run tests
zig build test --summary all

# Cross-compile for all supported platforms
zig build cross

# Run the GUI (Windows only)
zig build run-gui
```

## Usage

### CLI

```
convertsie [--vector-asc | --can-err] <input.sie> <output.[h5|txt|csv|xlsx|asc]>
```

The output format is normally determined from the file extension. The two force
flags override extension dispatch when a CSV/ASCII extension is ambiguous:

- `--vector-asc` — write a Vector-style CAN ASCII log (`.asc`). Only raw CAN
  channels are emitted; other channels are skipped.
- `--can-err` — extract J1939 DM1 active DTCs from raw CAN channels and write
  a CSV. Non-CAN files produce no output.

```bash
convertsie recording.sie recording.h5                 # HDF5 export
convertsie recording.sie recording.txt                # ASCII text export
convertsie recording.sie recording.csv                # CSV export
convertsie recording.sie recording.xlsx               # Excel export
convertsie recording.sie recording.asc                # Vector-style CAN ASCII
convertsie --can-err recording.sie CANErr-recording.csv   # J1939 DM1 errors
```

### GUI (Windows only)

Run `convertsie-gui.exe` or `zig build run-gui`. The GUI provides:

- Drag-and-drop or browse for `.sie` files
- Six output-format checkboxes: **H5**, **TXT**, **CSV**, **XLSX**,
  **Vector Style ASCII (CAN only)**, **J1939 CAN Errors (CSV)**
- Automatic output filename generation (`Vector-<name>.asc`,
  `CANErr-<name>.csv`, etc.)
- Persisted format selections in `%APPDATA%\ConvertSIE\config.bin`
- Automatic Windows light/dark theme detection
- Opt-in debug console (bottom-right "debug console" link) with UTF-8 I/O

### HDF5 Output Hierarchy

```
/                           (root — file-level tags as attributes)
├── <test_name>/            (one group per test — test tags as attributes)
│   ├── <channel_name>/     (one group per channel — channel tags as attributes)
│   │   ├── dim0            (chunked f64 dataset — dimension 0 data)
│   │   ├── dim1            (chunked f64 dataset — dimension 1 data)
│   │   └── ...
│   └── <raw_can_channel>/  (raw CAN channels — raw_can="true" attribute)
│       ├── dim0            (chunked f64 dataset — frame timestamps)
│       ├── raw_bytes       (chunked u8 dataset — frames padded to 8 bytes)
│       └── raw_dlc         (chunked u8 dataset — actual frame length per row)
└── ...
```

All chunked datasets use a 4096-row chunk size and unlimited max size. Raw CAN
channels are stored byte-exact rather than as floats; the `raw_can_encoding`
attribute on the channel group documents the layout (currently
`padded_uint8_dlc`).

### CSV / XLSX Layout

The CSV/XLSX exporters group time-series channels that share a common sample
rate and row count under a single shared time column; everything else (raw CAN,
non-time-series, mismatched rates) gets its own block. Blocks are separated by a
blank column.

```
Test Name: <name>
Start Time: <time>

       , Channel_A, Channel_B,    , Channel_C
       , Units_A,   Units_B,      , Units_C
       , Rate_A,    Rate_B,       , Rate_C
Time(S), dim1,      dim1,         , Time(S), dim1
0.02,    10.5,      25.3,         , 0.01,    100.0
0.04,    11.2,      25.4,         , 0.02,    101.5
...
```

The XLSX export additionally splits across multiple sheets when row count
exceeds Excel's 1,048,576-row limit.

### Vector-Style ASCII (`.asc`)

CAN-only export compatible with Vector CANalyzer log readers. Each raw CAN
channel becomes a stream of timestamped frame records. Non-CAN channels are
skipped entirely; if a file contains no CAN channels, no output file is
created.

### J1939 CAN Errors (`--can-err`)

Scans raw CAN channels for J1939 DM1 (PGN 0xFECA) messages and extracts active
diagnostic trouble codes (SPN/FMI/OC). Produces a CSV with one row per DTC
occurrence. Multi-channel inputs yield a single combined CSV with a channel
column. Ported from
[CanErrFindr-Zig](https://github.com/efollman/CanErrFindr-Zig) (MIT).

## Dependencies

| Dependency | Source | Purpose |
|---|---|---|
| **HDF5 2.1.1** | [HDFGroup/hdf5 tarball](https://github.com/HDFGroup/hdf5/archive/refs/tags/2.1.1.tar.gz) | Hierarchical data format library (compiled from C source) |
| **libsie-zig** | [efollman/libsie-zig](https://github.com/efollman/libsie-zig) | SIE file parser |
| **raylib-zig** | [raylib-zig/raylib-zig](https://github.com/raylib-zig/raylib-zig) (lazy, Windows GUI only) | GUI framework with raygui |

All dependencies are declared in `build.zig.zon` and fetched automatically by the Zig build system. The raylib dependency is lazy and only fetched when building the GUI on Windows.

## Cross-Compilation

The build system supports cross-compilation for five targets from any host with Zig installed:

| Target | CLI Output Path |
|---|---|
| `x86_64-linux` | `zig-out/linux-x86_64/convertsie` |
| `aarch64-linux` | `zig-out/linux-aarch64/convertsie` |
| `x86_64-windows` | `zig-out/windows-x86_64/convertsie.exe` |
| `x86_64-macos` | `zig-out/macos-x86_64/convertsie` |
| `aarch64-macos` | `zig-out/macos-aarch64/convertsie` |

The GUI (`convertsie-gui.exe`) is built automatically alongside the CLI when targeting Windows.

## Project Structure

```
ConvertSIE/
├── build.zig                 Build system configuration
├── build.zig.zon             Package manifest and dependencies
├── hdf5_config/              Custom HDF5 build configuration
│   ├── H5pubconf.h           Cross-platform config header
│   └── H5build_settings.c    Stub for H5build_settings[] symbol
├── src/
│   ├── main.zig              CLI entry point (dispatches by extension / flag)
│   ├── gui.zig               Windows GUI application (raylib/raygui)
│   ├── root.zig              Library module — re-exports all exporters
│   ├── common.zig            Shared SIE reading and data structures
│   ├── hdf5.zig              Zig bindings for the HDF5 C API
│   ├── hdf5_export.zig       HDF5 export implementation
│   ├── ascii_export.zig      ASCII text export implementation
│   ├── csv_export.zig        CSV export implementation
│   ├── xlsx_export.zig       XLSX export implementation (pure Zig)
│   ├── vector_asc_export.zig Vector-style CAN ASCII export
│   ├── can_err.zig           J1939 DM1 DTC parser (ported from CanErrFindr-Zig)
│   └── can_err_export.zig    SIE→CANErr CSV wrapper
├── test/
│   └── data/                 SIE test files
└── docs/
    ├── ARCHITECTURE.md       Module responsibilities and data flow
    ├── HDF5_BUILD.md         How HDF5 is compiled from source
    └── CROSS_COMPILATION.md  Supported targets and platform details
```

## Requirements

- Zig 0.15.2+

## Author

Evan Follman

## Source Code

https://github.com/efollman/ConvertSIE

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
