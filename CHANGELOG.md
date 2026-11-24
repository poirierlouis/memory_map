# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added
- **Native Linux Implementation**: Pure `dart:ffi` bindings to `libc` requiring
  no external C/C++ build toolchains.

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

[0.1.0]: https://github.com/poirierlouis/memory_map/releases/tag/v0.1.0
