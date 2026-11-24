import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'mm_file.dart';

// --- Linux Constants ---
const int _oRdonly = 0x0000;
const int _oRdwr = 0x0002;
const int _oCreat = 0x0040;
const int _oTrunc = 0x0200;
const int _defaultCreateMode = 0x1B6; // 0666

const int _seekEnd = 2;

const int _protRead = 0x1;
const int _protWrite = 0x2;

const int _mapShared = 0x01;
const int _mapPrivate = 0x02;

const int _msSync = 4;
const int _scPagesize = 30;

// --- Native C Type Signatures ---
typedef _OpenNative = Int32 Function(
  Pointer<Utf8> pathname,
  Int32 flags,
  VarArgs<(Uint32,)>,
);
typedef _OpenDart = int Function(Pointer<Utf8> pathname, int flags, int mode);

typedef _LseekNative = Int64 Function(Int32 fd, Int64 offset, Int32 whence);
typedef _LseekDart = int Function(int fd, int offset, int whence);

typedef _FtruncateNative = Int32 Function(Int32 fd, Int64 length);
typedef _FtruncateDart = int Function(int fd, int length);

typedef _MmapNative = Pointer<Uint8> Function(
  Pointer<Void> addr,
  IntPtr length,
  Int32 prot,
  Int32 flags,
  Int32 fd,
  Int64 offset,
);
typedef _MmapDart = Pointer<Uint8> Function(
  Pointer<Void> addr,
  int length,
  int prot,
  int flags,
  int fd,
  int offset,
);

typedef _MunmapNative = Int32 Function(Pointer<Uint8> addr, IntPtr length);
typedef _MunmapDart = int Function(Pointer<Uint8> addr, int length);

typedef _MsyncNative = Int32 Function(
  Pointer<Uint8> addr,
  IntPtr length,
  Int32 flags,
);
typedef _MsyncDart = int Function(Pointer<Uint8> addr, int length, int flags);

typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);

typedef _SysconfNative = Long Function(Int32 name);
typedef _SysconfDart = int Function(int name);

typedef _ErrnoLocationNative = Pointer<Int32> Function();
typedef _ErrnoLocationDart = Pointer<Int32> Function();

typedef _StrerrorNative = Pointer<Utf8> Function(Int32 errnum);
typedef _StrerrorDart = Pointer<Utf8> Function(int errnum);

class _Libc {
  static final DynamicLibrary _lib = DynamicLibrary.process();

  static final open = _lib.lookupFunction<_OpenNative, _OpenDart>('open');
  static final lseek = _lib.lookupFunction<_LseekNative, _LseekDart>('lseek');
  static final ftruncate = _lib
      .lookupFunction<_FtruncateNative, _FtruncateDart>('ftruncate');
  static final mmap = _lib.lookupFunction<_MmapNative, _MmapDart>('mmap');
  static final munmap = _lib.lookupFunction<_MunmapNative, _MunmapDart>(
    'munmap',
  );
  static final msync = _lib.lookupFunction<_MsyncNative, _MsyncDart>('msync');
  static final close = _lib.lookupFunction<_CloseNative, _CloseDart>('close');
  static final sysconf = _lib.lookupFunction<_SysconfNative, _SysconfDart>(
    'sysconf',
  );
  static final errnoLocation = _lib
      .lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>(
        '__errno_location',
      );
  static final strerror = _lib.lookupFunction<_StrerrorNative, _StrerrorDart>(
    'strerror',
  );

  static final int pageSize = _resolvePageSize();

  static int _resolvePageSize() {
    final size = sysconf(_scPagesize);
    return size > 0 ? size : 4096;
  }

  static int get errno => errnoLocation().value;

  static String errorMessage([int? err]) {
    final code = err ?? errno;
    final msgPtr = strerror(code);
    final msg = msgPtr == nullptr ? 'Unknown error' : msgPtr.toDartString();
    return '$msg (errno: $code)';
  }
}

class LinuxMMFile implements MMFile {
  final int _fd;
  final Pointer<Uint8> _ptr;
  final Uint8List _bytes;

  @override
  final int length;

  bool _isClosed = false;

  LinuxMMFile._(this._fd, this._ptr, this.length)
    : _bytes = _ptr.asTypedList(length);

  factory LinuxMMFile.open(
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

    final (openAccess, prot, mapFlags) = switch (mode) {
      MMFileMode.readOnly => (_oRdonly, _protRead, _mapShared),
      MMFileMode.readWrite => (_oRdwr, _protRead | _protWrite, _mapShared),
      MMFileMode.copyOnWrite => (_oRdonly, _protRead | _protWrite, _mapPrivate),
    };

    final openDisposition = switch (disposition) {
      MMFileDisposition.openExisting => 0,
      MMFileDisposition.openOrCreate => _oCreat,
      MMFileDisposition.createAlways => _oCreat | _oTrunc,
    };

    final pathPtr = path.toNativeUtf8(allocator: calloc);
    int fd = -1;

    try {
      fd = _Libc.open(
        pathPtr,
        openAccess | openDisposition,
        _defaultCreateMode,
      );
      if (fd < 0) {
        throw StateError('open failed: ${_Libc.errorMessage()}');
      }

      final currentFileSize = _getFileSize(fd);
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
        _resizeFile(fd, targetEnd);
      } else if (targetEnd > currentFileSize) {
        throw RangeError(
          'Requested mapping range [$offset, $targetEnd) exceeds file size ($currentFileSize).',
        );
      }

      final ptr = _Libc.mmap(nullptr, mapLength, prot, mapFlags, fd, offset);
      if (ptr == nullptr || ptr.address == -1) {
        throw StateError('mmap failed: ${_Libc.errorMessage()}');
      }

      return LinuxMMFile._(fd, ptr, mapLength);
    } catch (_) {
      if (fd >= 0) {
        _Libc.close(fd);
      }

      rethrow;
    } finally {
      calloc.free(pathPtr);
    }
  }

  static int _getFileSize(int fd) {
    final size = _Libc.lseek(fd, 0, _seekEnd);
    if (size < 0) {
      throw StateError('lseek failed: ${_Libc.errorMessage()}');
    }

    return size;
  }

  static void _resizeFile(int fd, int newSize) {
    if (_Libc.ftruncate(fd, newSize) != 0) {
      throw StateError('ftruncate failed: ${_Libc.errorMessage()}');
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

    if (flushLen == 0) {
      return;
    }

    final pageSize = _Libc.pageSize;
    final startAddr = _ptr.address + offset;
    final alignedAddr = startAddr & ~(pageSize - 1);
    final alignedLen = (startAddr - alignedAddr) + flushLen;

    final alignedPtr = Pointer<Uint8>.fromAddress(alignedAddr);
    if (_Libc.msync(alignedPtr, alignedLen, _msSync) != 0) {
      throw StateError('msync failed: ${_Libc.errorMessage()}');
    }
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _Libc.munmap(_ptr, length);
    _Libc.close(_fd);
  }
}
