import 'dart:typed_data';

import 'stub_mm_file.dart' if (dart.library.io) 'io_mm_file.dart';

/// Access modes for memory-mapped files.
enum MMFileMode {
  /// Maps the file as read-only. Writes to [bytes] will throw or segfault.
  readOnly,

  /// Maps the file for reading and writing. Changes are written back to disk.
  readWrite,

  /// Copy-on-write: reads from the file, but writes remain private in RAM
  /// and are never flushed back to the underlying file on disk.
  copyOnWrite,
}

/// Controls whether the file should be created, opened, or truncated.
enum MMFileDisposition {
  /// Opens the file only if it already exists. Throws if not found.
  openExisting,

  /// Opens the file if it exists, or creates a new empty file if it does not.
  openOrCreate,

  /// Always creates a new file. Overwrites and truncates if it already exists.
  createAlways,
}

/// An OS-agnostic memory-mapped file.
abstract interface class MMFile {
  /// Opens or creates a file at [path] and maps it into memory.
  ///
  /// - [mode]: Memory access mode ([MMFileMode.readOnly], [MMFileMode.readWrite], etc.).
  /// - [disposition]: Whether to open an existing file or create/overwrite one.
  /// - [offset]: Byte offset in the file where mapping begins (must align with OS granularity).
  /// - [length]: Number of bytes to map. Required when creating a new empty file,
  ///   or when resizing an existing file. If omitted for an existing file, maps until EOF.
  /// - [resizeFile]: If `true` and [mode] is [MMFileMode.readWrite], resizes the
  ///   underlying file on disk to `offset + length` (extending or truncating it).
  factory MMFile.open(
    String path, {
    MMFileMode mode = .readOnly,
    MMFileDisposition disposition = .openExisting,
    int offset = 0,
    int? length,
    bool resizeFile = false,
  }) => openMMFile(
    path,
    mode: mode,
    disposition: disposition,
    offset: offset,
    length: length,
    resizeFile: resizeFile,
  );

  /// Zero-copy view of the mapped memory region.
  ///
  /// Throws a [StateError] if the mapping has already been closed.
  Uint8List get bytes;

  /// The length of the mapped region in bytes.
  int get length;

  /// Whether this memory mapping has been unmapped and closed.
  bool get isClosed;

  /// Flushes modified bytes in the mapped region back to the storage device.
  ///
  /// If [offset] and [length] are omitted, the entire mapped view is flushed.
  void flush({int offset = 0, int? length});

  /// Unmaps the memory view and releases all underlying OS file handles.
  void close();
}
