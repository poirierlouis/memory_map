import 'mm_file.dart';

MMFile openMMFile(
  String path, {
  required MMFileMode mode,
  required MMFileDisposition disposition,
  required int offset,
  int? length,
  required bool resizeFile,
}) {
  throw UnsupportedError(
    'Memory-mapped files are not supported on this platform.',
  );
}

int getAllocationGranularity() {
  throw UnsupportedError(
    'Memory-mapped files are not supported on this platform.',
  );
}
