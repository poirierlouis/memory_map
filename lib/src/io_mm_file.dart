import 'dart:io' show Platform;

import 'linux_mm_file.dart';
import 'mm_file.dart';
import 'windows_mm_file.dart';

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
  if (Platform.isLinux) {
    return LinuxMMFile.open(
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

int getAllocationGranularity() {
  if (Platform.isWindows) {
    return WindowsMMFile.allocationGranularity;
  }
  if (Platform.isLinux) {
    return LinuxMMFile.allocationGranularity;
  }
  throw UnsupportedError(
    'Unsupported operating system: ${Platform.operatingSystem}',
  );
}
