# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Native Linux Implementation**: Added pure `dart:ffi` bindings to `libc` with support for both 32-bit and 64-bit Linux systems.
- **Allocation Granularity**: Added `MMFile.allocationGranularity` to query the host operating system's memory allocation granularity.
- **Automatic Offset Alignment**: Added internal alignment for arbitrary `offset` values in `MMFile.open()`, enabling portable byte-level offsets across Windows and Linux.

### Changed
- **Automatic Resource Cleanup**: Memory mappings and OS file handles are now automatically released during garbage collection if `close()` is omitted.
- **Read-Only Protection**: `MMFile.bytes` now returns an unmodifiable `Uint8List` view in `MMFileMode.readOnly`, throwing `UnsupportedError` on write attempts.

### Fixed
- **Synchronous Windows Flush**: `MMFile.flush()` on Windows now flushes file buffers synchronously to disk, matching Linux durability guarantees.
- **Zero-Length Flush Parity**: `MMFile.flush(length: 0)` now performs a no-op on Windows to match Linux behavior.
- **Safe Open Validation**: `MMFile.open()` now validates parameters and directory paths early, preserving existing files and clean disk state on error.

## [0.1.0] - 2026-11-24

### Added
- **Agnostic `MMFile` Interface**: OS-agnostic memory-mapped file abstraction
  exposing zero-copy `Uint8List` views (`bytes`), explicit `flush()`, and safe
  `close()` lifecycle management.
- **Access & Disposition Controls**: Added `MMFileMode` (`readOnly`,
  `readWrite`, `copyOnWrite`) and `MMFileDisposition` (`openExisting`,
  `openOrCreate`, `createAlways`) along with `resizeFile` support for extending
  or truncating files on disk.
- **Native Windows Implementation**: Pure `dart:ffi` bindings to `kernel32.dll`
  requiring no external C/C++ build toolchains.
- **Platform Routing**: Conditional imports and runtime platform checks that
  gracefully throw `UnsupportedError` on unsupported platforms (such as Web).

[unreleased]: https://github.com/poirierlouis/memory_map/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/poirierlouis/memory_map/releases/tag/v0.1.0
