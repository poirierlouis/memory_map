@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:memory_map/memory_map.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memory_map_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String tempFilePath(String name) =>
      '${tempDir.path}${Platform.pathSeparator}$name';

  group('MMFile (Windows) - Lifecycle & Creation', () {
    test('creates a new file with createAlways and writes data to disk', () {
      final path = tempFilePath('create_always.bin');
      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        disposition: MMFileDisposition.createAlways,
        length: 256,
      );

      expect(file.length, 256);
      expect(file.isClosed, isFalse);

      file.bytes[0] = 0xDE;
      file.bytes[1] = 0xAD;
      file.bytes[255] = 0xFF;
      file.flush();
      file.close();

      expect(file.isClosed, isTrue);

      // Verify persisted content via standard dart:io
      final diskBytes = File(path).readAsBytesSync();
      expect(diskBytes.length, 256);
      expect(diskBytes[0], 0xDE);
      expect(diskBytes[1], 0xAD);
      expect(diskBytes[255], 0xFF);
    });

    test('openOrCreate opens existing file without truncating data', () {
      final path = tempFilePath('open_or_create.bin');
      File(path).writeAsBytesSync([10, 20, 30, 40]);

      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        disposition: MMFileDisposition.openOrCreate,
      );

      expect(file.length, 4);
      expect(file.bytes, orderedEquals([10, 20, 30, 40]));
      file.close();
    });

    test('openExisting throws StateError when file does not exist', () {
      final path = tempFilePath('non_existent.bin');

      expect(
        () => MMFile.open(
          path,
          mode: MMFileMode.readOnly,
          disposition: MMFileDisposition.openExisting,
        ),
        throwsStateError,
      );
    });

    test('close() is idempotent and prevents subsequent access', () {
      final path = tempFilePath('closed_guard.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      final file = MMFile.open(path);
      file.close();
      expect(() => file.close(), returnsNormally); // Second close is a no-op

      expect(() => file.bytes, throwsStateError);
      expect(() => file.flush(), throwsStateError);
    });
  });

  group('MMFile (Windows) - Access Modes', () {
    test('readOnly maps entire file accurately', () {
      final path = tempFilePath('readonly.bin');
      final expected = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      File(path).writeAsBytesSync(expected);

      final file = MMFile.open(path, mode: MMFileMode.readOnly);
      try {
        expect(file.length, 1024);
        expect(file.bytes, orderedEquals(expected));
      } finally {
        file.close();
      }
    });

    test('copyOnWrite isolates memory edits from disk', () {
      final path = tempFilePath('cow.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      final file = MMFile.open(path, mode: MMFileMode.copyOnWrite);
      try {
        file.bytes[0] = 99;
        expect(file.bytes[0], 99);
      } finally {
        file.close();
      }

      // Disk file must remain untouched
      expect(File(path).readAsBytesSync(), orderedEquals([1, 2, 3, 4]));
    });
  });

  group('MMFile (Windows) - Offsets & Resizing', () {
    test('maps with a 64KB-aligned non-zero offset', () {
      const granularity =
          64 * 1024; // Windows allocation granularity (65,536 bytes)
      final path = tempFilePath('offset.bin');

      final initial = Uint8List(granularity + 128);
      initial[granularity] = 0xAA;
      initial[granularity + 127] = 0xBB;
      File(path).writeAsBytesSync(initial);

      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        offset: granularity,
        length: 128,
      );

      try {
        expect(file.length, 128);
        expect(file.bytes[0], 0xAA);
        expect(file.bytes[127], 0xBB);

        file.bytes[1] = 0xCC;
        file.flush();
      } finally {
        file.close();
      }

      final updated = File(path).readAsBytesSync();
      expect(updated[granularity + 1], 0xCC);
    });

    test('fails when offset is not aligned to Windows 64KB granularity', () {
      final path = tempFilePath('unaligned_offset.bin');
      File(path).writeAsBytesSync(Uint8List(8192));

      expect(
        () => MMFile.open(path, offset: 4096, length: 1024),
        throwsStateError, // MapViewOfFile fails with ERROR_MAPPED_ALIGNMENT (1132)
      );
    });

    test('resizes (extends and truncates) an existing file when resizeFile is true', () {
      final path = tempFilePath('resize.bin');
      File(path).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

      // 1. Extend from 4 bytes to 16 bytes
      final extended = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        length: 16,
        resizeFile: true,
      );
      extended.bytes[15] = 0x7F;
      extended.flush();
      extended.close();

      expect(File(path).lengthSync(), 16);
      expect(File(path).readAsBytesSync()[15], 0x7F);

      // 2. Truncate from 16 bytes down to 2 bytes
      final truncated = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        length: 2,
        resizeFile: true,
      );
      expect(truncated.bytes, orderedEquals([1, 2]));
      truncated.close();

      expect(File(path).lengthSync(), 2);
    });
  });

  group('MMFile (Windows) - Validation & Bounds', () {
    test('throws ArgumentError on invalid arguments', () {
      final path = tempFilePath('validation.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      // Negative offset
      expect(() => MMFile.open(path, offset: -1), throwsArgumentError);

      // Zero length
      expect(() => MMFile.open(path, length: 0), throwsArgumentError);

      // resizeFile without readWrite mode
      expect(
        () => MMFile.open(
          path,
          mode: MMFileMode.readOnly,
          length: 10,
          resizeFile: true,
        ),
        throwsArgumentError,
      );

      // createAlways without readWrite mode
      expect(
        () => MMFile.open(
          path,
          mode: MMFileMode.readOnly,
          disposition: MMFileDisposition.createAlways,
          length: 10,
        ),
        throwsArgumentError,
      );
    });

    test('throws RangeError when readOnly mapping exceeds file size', () {
      final path = tempFilePath('eof_bounds.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      expect(
        () => MMFile.open(path, mode: MMFileMode.readOnly, length: 100),
        throwsRangeError,
      );
    });

    test('flush validates offset and length bounds', () {
      final path = tempFilePath('flush_bounds.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      final file = MMFile.open(path, mode: MMFileMode.readWrite);
      try {
        expect(() => file.flush(offset: -1), throwsRangeError);
        expect(() => file.flush(offset: 2, length: 5), throwsRangeError);
        expect(() => file.flush(offset: 1, length: 3), returnsNormally);
      } finally {
        file.close();
      }
    });
  });
}
