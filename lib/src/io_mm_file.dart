import 'dart:io' show Platform;

import 'mm_file.dart';
import 'windows_mm_file.dart';

// import 'posix_mm_file.dart';

MMFile openMMFile(
  String path, {
  required MMFileMode mode,
  required MMFileDisposition disposition,
  required int offset,
  int? length,
  required bool resizeFile,
}) {
  if (Platform.isWindows) {
    return WindowsMMFile.open(
      path,
      mode: mode,
      disposition: disposition,
      offset: offset,
      length: length,
      resizeFile: resizeFile,
    );
  }
  throw UnsupportedError(
    'Unsupported operating system: ${Platform.operatingSystem}',
  );
}
