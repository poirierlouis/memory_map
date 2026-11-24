/// Cross-platform, zero-copy memory-mapped file (mmap) support for Dart using `dart:ffi`.
///
/// This library exposes [MMFile], an OS-agnostic interface for mapping files
/// directly into virtual memory as a [Uint8List] without copying data into
/// user-space buffers or incurring intermediate I/O overhead.
///
/// ## Platform Support
/// * **Windows**: Implemented via `dart:ffi` bindings to the `kernel32.dll`
///   library.
/// * **Linux**: Implemented via `dart:ffi` bindings to the standard C library.
/// * **Web / Unsupported Platforms**: Gracefully throws an [UnsupportedError]
///   at runtime via conditional imports.
///
/// ## Key Features
/// * **Access Modes ([MMFileMode])**: Supports [MMFileMode.readOnly],
///   [MMFileMode.readWrite], and private [MMFileMode.copyOnWrite] mappings.
/// * **File Creation & Resizing ([MMFileDisposition])**: Open existing files,
///   create new files, or extend/truncate files on disk prior to mapping.
/// * **Explicit Lifecycle & Safety**: Guards against use-after-free access
///   violations after [MMFile.close] and provides [MMFile.flush] to synchronize
///   modified byte ranges back to storage.
///
/// ## Usage
///
/// ```dart
/// import 'dart:typed_data';
/// import 'package:memory_map/memory_map.dart';
///
/// void main() {
///   // Create or overwrite a 1 MB file and map it for reading and writing
///   final file = MMFile.open(
///     'example.bin',
///     mode: MMFileMode.readWrite,
///     disposition: MMFileDisposition.createAlways,
///     length: 1024 * 1024,
///   );
///
///   try {
///     // Read and write directly to mapped memory as a standard Uint8List
///     final Uint8List data = file.bytes;
///     data[0] = 0xCA;
///     data[1] = 0xFE;
///
///     // Persist changes to disk
///     file.flush();
///   } finally {
///     // Always unmap the view and release OS handles
///     file.close();
///   }
/// }
/// ```
///
/// ## Important Constraints
/// * **Alignment**: When specifying a non-zero `offset`, it must align with the
///   host operating system's memory allocation granularity (typically 64 KB on
///   Windows and 4 KB on POSIX systems).
/// * **Resource Management**: Always call [MMFile.close] when finished. Any
///   subsequent access to [MMFile.bytes] or [MMFile.flush] will throw a
///   [StateError].
library;

export 'src/mm_file.dart';
