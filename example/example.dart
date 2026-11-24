import 'dart:io';
import 'dart:typed_data';

import 'package:memory_map/memory_map.dart';

void main() {
  final kPath = "${Directory.current.path}\\test.bin";

  {
    // Read Write
    print("| Mode: readwrite");
    print("| Path: $kPath");
    print("| Size: 1024 B");

    final file = MMFile.open(
      kPath,
      mode: .readWrite,
      disposition: .openOrCreate,
      length: 1024,
    );

    for (int i = 0; i < 1024; ++i) {
      file.bytes[i] = i % 256;
    }

    file.flush();
    file.close();
    print("");
  }

  {
    // Read Only
    print("| Mode: readonly");
    print("| Path: $kPath");
    print("| ");

    final file = MMFile.open(
      kPath,
      mode: .readOnly,
      disposition: .openExisting,
    );

    print("| Size: ${file.bytes.lengthInBytes} B");

    final view = ByteData.sublistView(file.bytes);
    var count = 0;
    for (int i = 0; i < 256; i++) {
      if (view.getUint8(256 + i) == i) {
        count++;
      }
    }

    print("| Match: ${count == 256} ($count / 256)");

    file.close();
    print("");
  }
}
