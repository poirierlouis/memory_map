# memory_map

Zero-copy memory-mapped file (`mmap`) support for Dart using pure `dart:ffi`, 
requiring no external C/C++ build toolchains.

## Features

- **Zero-Copy Memory Access**: Exposes mapped files directly as a standard 
  `Uint8List` without copying data into user-space buffers.
- **Multiple Access Modes**: Supports `readOnly`, `readWrite`, and private 
  `copyOnWrite` mappings via `MMFileMode`.
- **File Creation & Resizing**: Open existing files, create new ones, or resize
  (extend/truncate) files on disk using `MMFileDisposition` and `resizeFile`.
- **Explicit Resource Safety**: Guards against use-after-free access after 
  `close()` and provides `flush()` to persist modified byte ranges back to disk.
- **Native Cross-Platform Support**: Calls Win32 APIs (`kernel32.dll`) on
  Windows and POSIX `libc` APIs on Linux directly via `dart:ffi`.

## Getting started

**Requirements:**
- Dart SDK `>=3.0.0`
- **Supported Platforms**: Windows and Linux (macOS/Android planned; Web 
  throws an `UnsupportedError`).

Add `memory_map` to your `pubspec.yaml`:

```yaml
dependencies:
  memory_map: ^0.1.0
```

## Usage

```dart
import 'package:memory_map/memory_map.dart';

void main() {
  // Create or overwrite a 1 MB file and map it into memory
  final file = MMFile.open(
    'example.bin',
    mode: MMFileMode.readWrite,
    disposition: MMFileDisposition.createAlways,
    length: 1024 * 1024,
  );

  try {
    // Read and write directly to mapped memory as a Uint8List
    file.bytes[0] = 0xCA;
    file.bytes[1] = 0xFE;

    // Persist changes to storage
    file.flush();
  } finally {
    // Always unmap the view and release OS handles
    file.close();
  }
}
```

## Additional information

- **Alignment**: Non-zero `offset` values are automatically aligned to 
  `MMFile.allocationGranularity` internally (typically 64 KB on Windows and 
  page size — usually 4 KB — on Linux).
- **Lifecycle**: Always call `file.close()` when finished. Accessing `bytes` or 
  calling `flush()` on a closed `MMFile` throws a `StateError`.
- **Issues & Contributions**: Bug reports and pull requests are welcome on the 
  package repository.