import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsPipeTransport {
  HANDLE? _handle;

  bool connect() {
    for (var i = 0; i < 10; i++) {
      final path = '\\\\.\\pipe\\discord-ipc-$i';
      final pathPtr = path.toNativeUtf16();
      try {
        final result = CreateFile(
          PCWSTR(pathPtr),
          GENERIC_READ | GENERIC_WRITE,
          FILE_SHARE_NONE,
          null,
          OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL,
          null,
        );
        if (result.value.address != INVALID_HANDLE_VALUE.address) {
          _handle = result.value;
          return true;
        }
      } finally {
        calloc.free(pathPtr);
      }
    }
    return false;
  }

  bool write(Uint8List bytes) {
    final handle = _handle;
    if (handle == null || bytes.isEmpty) return false;

    final buffer = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return WriteFile(handle, buffer, bytes.length, written, null).value;
    } finally {
      calloc.free(buffer);
      calloc.free(written);
    }
  }

  Uint8List? read(int maxBytes) {
    final handle = _handle;
    if (handle == null) return null;

    final buffer = calloc<Uint8>(maxBytes);
    final readCount = calloc<Uint32>();
    try {
      final result = ReadFile(handle, buffer, maxBytes, readCount, null);
      if (!result.value) return null;
      return Uint8List.fromList(buffer.asTypedList(readCount.value));
    } finally {
      calloc.free(buffer);
      calloc.free(readCount);
    }
  }

  void close() {
    final handle = _handle;
    _handle = null;
    if (handle != null) CloseHandle(handle);
  }
}
