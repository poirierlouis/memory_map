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

  group('MMFile - Lifecycle & Creation', () {
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

    test('openOrCreate creates a new file when it does not exist', () {
      final path = tempFilePath('open_or_create_new.bin');
      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        disposition: MMFileDisposition.openOrCreate,
        length: 16,
      );

      try {
        expect(file.length, 16);
        file.bytes[0] = 0x42;
        file.flush();
      } finally {
        file.close();
      }

      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), 16);
      expect(File(path).readAsBytesSync()[0], 0x42);
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

  group('MMFile - Access Modes', () {
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

    test('readOnly throws UnsupportedError when attempting to write', () {
      final path = tempFilePath('readonly_write.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      final file = MMFile.open(path, mode: MMFileMode.readOnly);
      try {
        expect(() => file.bytes[0] = 99, throwsUnsupportedError);
        expect(file.bytes[0], 1);
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

  group('MMFile - Offsets & Resizing', () {
    test('exposes a valid power-of-two allocationGranularity', () {
      final granularity = MMFile.allocationGranularity;
      expect(granularity, greaterThanOrEqualTo(4096));
      expect(granularity & (granularity - 1), 0);
    });

    test('maps with an allocationGranularity-aligned non-zero offset', () {
      final granularity = MMFile.allocationGranularity;
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

    test('maps with an unaligned offset (512 bytes) and flushes accurately', () {
      final path = tempFilePath('unaligned_offset.bin');
      final initial = Uint8List.fromList(
        List.generate(8192, (i) => i % 251),
      );
      File(path).writeAsBytesSync(initial);

      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        offset: 512,
        length: 1024,
      );
      try {
        expect(file.length, 1024);
        expect(file.bytes[0], initial[512]);
        expect(file.bytes[1023], initial[512 + 1023]);

        file.bytes[0] = 0xDE;
        file.bytes[1023] = 0xAD;
        file.flush();
      } finally {
        file.close();
      }

      final updated = File(path).readAsBytesSync();
      expect(updated[511], initial[511]);
      expect(updated[512], 0xDE);
      expect(updated[512 + 1023], 0xAD);
      expect(updated[512 + 1024], initial[512 + 1024]);
    });

    test('maps with unaligned offset and omitted length until EOF', () {
      final path = tempFilePath('unaligned_eof.bin');
      final initial = Uint8List.fromList(
        List.generate(5000, (i) => i % 256),
      );
      File(path).writeAsBytesSync(initial);

      final file = MMFile.open(path, offset: 333);
      try {
        expect(file.length, 5000 - 333);
        expect(file.bytes, orderedEquals(initial.sublist(333)));
      } finally {
        file.close();
      }
    });

    test('maps with offset 4096 (page-aligned on Linux, auto-aligned on Windows)', () {
      final path = tempFilePath('offset_4096.bin');
      final initial = Uint8List(8192);
      initial[4096] = 0x11;
      initial[4096 + 1023] = 0x22;
      File(path).writeAsBytesSync(initial);

      final file = MMFile.open(
        path,
        mode: MMFileMode.readWrite,
        offset: 4096,
        length: 1024,
      );
      try {
        expect(file.length, 1024);
        expect(file.bytes[0], 0x11);
        expect(file.bytes[1023], 0x22);

        file.bytes[10] = 0x33;
        file.flush();
      } finally {
        file.close();
      }

      final updated = File(path).readAsBytesSync();
      expect(updated[4096 + 10], 0x33);
    });

    test(
      'maps with page-aligned offset 4096 on Linux',
      () {
        expect(MMFile.allocationGranularity, 4096);
        final path = tempFilePath('linux_4096_offset.bin');
        final initial = Uint8List(8192);
        initial[4096] = 0x5A;
        File(path).writeAsBytesSync(initial);

        final file = MMFile.open(path, offset: 4096, length: 1024);
        try {
          expect(file.length, 1024);
          expect(file.bytes[0], 0x5A);
        } finally {
          file.close();
        }
      },
      testOn: 'linux',
    );

    test(
      'automatically extends file when readWrite mapping exceeds file size',
      () {
        final path = tempFilePath('auto_extend.bin');
        File(path).writeAsBytesSync([1, 2, 3, 4]);

        final file = MMFile.open(path, mode: MMFileMode.readWrite, length: 12);
        try {
          expect(file.length, 12);
          file.bytes[11] = 0x99;
          file.flush();
        } finally {
          file.close();
        }

        final diskBytes = File(path).readAsBytesSync();
        expect(diskBytes.length, 12);
        expect(diskBytes.sublist(0, 4), orderedEquals([1, 2, 3, 4]));
        expect(diskBytes[11], 0x99);
      },
    );

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

  group('MMFile - Validation & Bounds', () {
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

    test('throws RangeError when non-readWrite mapping exceeds file size', () {
      final path = tempFilePath('eof_bounds.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      expect(
        () => MMFile.open(path, mode: MMFileMode.readOnly, length: 100),
        throwsRangeError,
      );
      expect(
        () => MMFile.open(path, mode: MMFileMode.copyOnWrite, length: 100),
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

    test('partial unaligned flush persists modified range to disk', () {
      final path = tempFilePath('partial_flush.bin');
      File(path).writeAsBytesSync([0, 0, 0, 0, 0, 0, 0, 0]);

      final file = MMFile.open(path, mode: MMFileMode.readWrite);
      try {
        file.bytes[1] = 0x11;
        file.bytes[2] = 0x22;
        file.bytes[3] = 0x33;
        file.flush(offset: 1, length: 3);
      } finally {
        file.close();
      }

      expect(
        File(path).readAsBytesSync(),
        orderedEquals([0, 0x11, 0x22, 0x33, 0, 0, 0, 0]),
      );
    });

    test('flush validates against 64-bit integer overflow and allows length: 0', () {
      final path = tempFilePath('flush_overflow.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      final file = MMFile.open(path, mode: MMFileMode.readWrite);
      try {
        expect(() => file.flush(offset: 0, length: 0), returnsNormally);
        expect(
          () => file.flush(offset: 2, length: 0x7FFFFFFFFFFFFFFF),
          throwsRangeError,
        );
      } finally {
        file.close();
      }
    });

    test('throws StateError when trying to map a directory', () {
      expect(
        () => MMFile.open(tempDir.path, mode: MMFileMode.readOnly),
        throwsStateError,
      );
    });

    test('failed openOrCreate does not leave behind an empty file', () {
      final path = tempFilePath('no_leak_empty.bin');
      expect(
        () => MMFile.open(
          path,
          mode: MMFileMode.copyOnWrite,
          disposition: MMFileDisposition.openOrCreate,
          length: 16,
        ),
        throwsRangeError,
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('createAlways with invalid length does not truncate existing file', () {
      final path = tempFilePath('no_truncate_invalid.bin');
      File(path).writeAsBytesSync([1, 2, 3, 4]);

      expect(
        () => MMFile.open(
          path,
          mode: MMFileMode.readWrite,
          disposition: MMFileDisposition.createAlways,
        ),
        throwsArgumentError,
      );
      expect(File(path).readAsBytesSync(), orderedEquals([1, 2, 3, 4]));
    });
  });
}
