import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'mm_file.dart';

// --- Win32 Constants ---
const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _fileShareRead = 0x00000001;
const int _fileShareWrite = 0x00000002;

// Creation Dispositions
const int _createAlways = 2;
const int _openExisting = 3;
const int _openAlways = 4;

// Move Methods for SetFilePointerEx
const int _fileBegin = 0;

const int _fileAttributeNormal = 0x00000080;
const int _invalidHandleValue = -1;

const int _pageReadOnly = 0x02;
const int _pageReadWrite = 0x04;
const int _pageWriteCopy = 0x08;

const int _fileMapCopy = 0x0001;
const int _fileMapWrite = 0x0002;
const int _fileMapRead = 0x0004;

// --- Native C Type Signatures ---
typedef _CreateFileWNative = IntPtr Function(
  Pointer<Uint16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  IntPtr hTemplateFile,
);
typedef _CreateFileWDart = int Function(
  Pointer<Uint16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

typedef _GetFileSizeExNative = Int32 Function(
  IntPtr hFile,
  Pointer<Int64> lpFileSize,
);
typedef _GetFileSizeExDart = int Function(int hFile, Pointer<Int64> lpFileSize);

typedef _SetFilePointerExNative = Int32 Function(
  IntPtr hFile,
  Int64 liDistanceToMove,
  Pointer<Int64> lpNewFilePointer,
  Uint32 dwMoveMethod,
);
typedef _SetFilePointerExDart = int Function(
  int hFile,
  int liDistanceToMove,
  Pointer<Int64> lpNewFilePointer,
  int dwMoveMethod,
);

typedef _SetEndOfFileNative = Int32 Function(IntPtr hFile);
typedef _SetEndOfFileDart = int Function(int hFile);

typedef _CreateFileMappingWNative = IntPtr Function(
  IntPtr hFile,
  Pointer<Void> lpFileMappingAttributes,
  Uint32 flProtect,
  Uint32 dwMaximumSizeHigh,
  Uint32 dwMaximumSizeLow,
  Pointer<Uint16> lpName,
);
typedef _CreateFileMappingWDart = int Function(
  int hFile,
  Pointer<Void> lpFileMappingAttributes,
  int flProtect,
  int dwMaximumSizeHigh,
  int dwMaximumSizeLow,
  Pointer<Uint16> lpName,
);

typedef _MapViewOfFileNative = Pointer<Uint8> Function(
  IntPtr hFileMappingObject,
  Uint32 dwDesiredAccess,
  Uint32 dwFileOffsetHigh,
  Uint32 dwFileOffsetLow,
  IntPtr dwNumberOfBytesToMap,
);
typedef _MapViewOfFileDart = Pointer<Uint8> Function(
  int hFileMappingObject,
  int dwDesiredAccess,
  int dwFileOffsetHigh,
  int dwFileOffsetLow,
  int dwNumberOfBytesToMap,
);

typedef _FlushViewOfFileNative = Int32 Function(
  Pointer<Uint8> lpBaseAddress,
  IntPtr dwNumberOfBytesToFlush,
);
typedef _FlushViewOfFileDart = int Function(
  Pointer<Uint8> lpBaseAddress,
  int dwNumberOfBytesToFlush,
);

typedef _UnmapViewOfFileNative = Int32 Function(Pointer<Uint8> lpBaseAddress);
typedef _UnmapViewOfFileDart = int Function(Pointer<Uint8> lpBaseAddress);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

class _Kernel32 {
  static final DynamicLibrary _lib = DynamicLibrary.open('kernel32.dll');

  static final createFileW = _lib
      .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
  static final getFileSizeEx = _lib
      .lookupFunction<_GetFileSizeExNative, _GetFileSizeExDart>(
        'GetFileSizeEx',
      );
  static final setFilePointerEx = _lib
      .lookupFunction<_SetFilePointerExNative, _SetFilePointerExDart>(
        'SetFilePointerEx',
      );
  static final setEndOfFile = _lib
      .lookupFunction<_SetEndOfFileNative, _SetEndOfFileDart>('SetEndOfFile');
  static final createFileMappingW = _lib
      .lookupFunction<_CreateFileMappingWNative, _CreateFileMappingWDart>(
        'CreateFileMappingW',
      );
  static final mapViewOfFile = _lib
      .lookupFunction<_MapViewOfFileNative, _MapViewOfFileDart>(
        'MapViewOfFile',
      );
  static final flushViewOfFile = _lib
      .lookupFunction<_FlushViewOfFileNative, _FlushViewOfFileDart>(
        'FlushViewOfFile',
      );
  static final unmapViewOfFile = _lib
      .lookupFunction<_UnmapViewOfFileNative, _UnmapViewOfFileDart>(
        'UnmapViewOfFile',
      );
  static final closeHandle = _lib
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final getLastError = _lib
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
}

class WindowsMMFile implements MMFile {
  final int _hFile;
  final int _hMap;
  final Pointer<Uint8> _ptr;
  final Uint8List _bytes;

  @override
  final int length;

  bool _isClosed = false;

  WindowsMMFile._(this._hFile, this._hMap, this._ptr, this.length)
    : _bytes = _ptr.asTypedList(length);

  factory WindowsMMFile.open(
    String path, {
    MMFileMode mode = .readOnly,
    MMFileDisposition disposition = .openExisting,
    int offset = 0,
    int? length,
    bool resizeFile = false,
  }) {
    if (offset < 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Offset must be non-negative.',
      );
    }

    if (resizeFile && mode != .readWrite) {
      throw ArgumentError('resizeFile requires MMFileMode.readWrite.');
    }

    if (disposition == .createAlways && mode != .readWrite) {
      throw ArgumentError(
        'MMFileDisposition.createAlways requires MMFileMode.readWrite.',
      );
    }

    final (desiredAccess, flProtect, mapAccess) = switch (mode) {
      MMFileMode.readOnly => (_genericRead, _pageReadOnly, _fileMapRead),
      MMFileMode.readWrite => (
        _genericRead | _genericWrite,
        _pageReadWrite,
        _fileMapRead | _fileMapWrite,
      ),
      MMFileMode.copyOnWrite => (_genericRead, _pageWriteCopy, _fileMapCopy),
    };

    final winDisposition = switch (disposition) {
      MMFileDisposition.openExisting => _openExisting,
      MMFileDisposition.openOrCreate => _openAlways,
      MMFileDisposition.createAlways => _createAlways,
    };

    final pathPtr = _toUtf16(path);
    int hFile = _invalidHandleValue;
    int hMap = 0;

    try {
      hFile = _Kernel32.createFileW(
        pathPtr,
        desiredAccess,
        _fileShareRead | _fileShareWrite,
        nullptr,
        winDisposition,
        _fileAttributeNormal,
        0,
      );

      if (hFile == _invalidHandleValue) {
        throw StateError(
          'CreateFileW failed with Win32 error: ${_Kernel32.getLastError()}',
        );
      }

      final currentFileSize = _getFileSize(hFile);
      final int mapLength;
      if (length != null) {
        mapLength = length;
      } else {
        mapLength = currentFileSize - offset;
      }
      if (mapLength <= 0) {
        throw ArgumentError(
          'Mapped length must be greater than 0 (got $mapLength). '
          'Provide an explicit [length] when creating or mapping an empty file.',
        );
      }

      final targetEnd = offset + mapLength;
      // Resize the physical file on disk if requested, or if extending in readWrite mode
      final shouldResize =
          resizeFile ||
          (mode == MMFileMode.readWrite && targetEnd > currentFileSize);
      if (shouldResize) {
        if (mode != MMFileMode.readWrite) {
          throw StateError(
            'Cannot map beyond EOF ($targetEnd > $currentFileSize) unless mode is MMFileMode.readWrite.',
          );
        }
        _resizeFile(hFile, targetEnd);
      } else if (targetEnd > currentFileSize) {
        throw RangeError(
          'Requested mapping range [$offset, $targetEnd) exceeds file size ($currentFileSize).',
        );
      }

      hMap = _Kernel32.createFileMappingW(
        hFile,
        nullptr,
        flProtect,
        (targetEnd >> 32) & 0xFFFFFFFF,
        targetEnd & 0xFFFFFFFF,
        nullptr,
      );
      if (hMap == 0) {
        throw StateError(
          'CreateFileMappingW failed with Win32 error: ${_Kernel32.getLastError()}',
        );
      }

      final ptr = _Kernel32.mapViewOfFile(
        hMap,
        mapAccess,
        (offset >> 32) & 0xFFFFFFFF,
        offset & 0xFFFFFFFF,
        mapLength,
      );
      if (ptr == nullptr) {
        throw StateError(
          'MapViewOfFile failed with Win32 error: ${_Kernel32.getLastError()}',
        );
      }

      return WindowsMMFile._(hFile, hMap, ptr, mapLength);
    } catch (_) {
      if (hMap != 0) {
        _Kernel32.closeHandle(hMap);
      }

      if (hFile != _invalidHandleValue) {
        _Kernel32.closeHandle(hFile);
      }

      rethrow;
    } finally {
      calloc.free(pathPtr);
    }
  }

  static int _getFileSize(int hFile) {
    final sizePtr = calloc<Int64>();
    try {
      if (_Kernel32.getFileSizeEx(hFile, sizePtr) == 0) {
        throw StateError(
          'GetFileSizeEx failed with Win32 error: ${_Kernel32.getLastError()}',
        );
      }

      return sizePtr.value;
    } finally {
      calloc.free(sizePtr);
    }
  }

  static void _resizeFile(int hFile, int newSize) {
    if (_Kernel32.setFilePointerEx(hFile, newSize, nullptr, _fileBegin) == 0) {
      throw StateError(
        'SetFilePointerEx failed with Win32 error: ${_Kernel32.getLastError()}',
      );
    }

    if (_Kernel32.setEndOfFile(hFile) == 0) {
      throw StateError(
        'SetEndOfFile failed with Win32 error: ${_Kernel32.getLastError()}',
      );
    }
  }

  @override
  bool get isClosed => _isClosed;

  @override
  Uint8List get bytes {
    if (_isClosed) {
      throw StateError('Cannot access bytes of a closed MMFile.');
    }

    return _bytes;
  }

  @override
  void flush({int offset = 0, int? length}) {
    if (_isClosed) {
      throw StateError('Cannot flush a closed MMFile.');
    }

    final flushLen = length ?? (this.length - offset);
    if (offset < 0 || flushLen < 0 || offset + flushLen > this.length) {
      throw RangeError(
        'Flush range [$offset, ${offset + flushLen}) out of bounds [0, ${this.length}).',
      );
    }

    final targetPtr = _ptr + offset;
    if (_Kernel32.flushViewOfFile(targetPtr, flushLen) == 0) {
      throw StateError(
        'FlushViewOfFile failed with Win32 error: ${_Kernel32.getLastError()}',
      );
    }
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _Kernel32.unmapViewOfFile(_ptr);
    _Kernel32.closeHandle(_hMap);
    _Kernel32.closeHandle(_hFile);
  }

  static Pointer<Uint16> _toUtf16(String str) {
    final units = str.codeUnits;
    final ptr = calloc<Uint16>(units.length + 1);
    final list = ptr.asTypedList(units.length + 1);
    list.setAll(0, units);
    list[units.length] = 0;
    return ptr;
  }
}
