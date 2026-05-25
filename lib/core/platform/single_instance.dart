import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bitta process'da bitta instance — har platforma o'z usuli bilan.
/// Returns false agar boshqa instance allaqachon ishlayotgan bo'lsa.
Future<bool> acquireSingleInstanceLock() async {
  if (Platform.isWindows) return _windowsLock();
  if (Platform.isLinux) return _unixLock();
  return true;
}

// === Windows: Named Mutex ===
typedef _CreateMutexWNative = IntPtr Function(
    Pointer<Void>, Int32, Pointer<Utf16>);
typedef _CreateMutexWDart = int Function(
    Pointer<Void>, int, Pointer<Utf16>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

bool _windowsLock() {
  try {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final createMutexW =
        kernel.lookupFunction<_CreateMutexWNative, _CreateMutexWDart>(
      'CreateMutexW',
    );
    final getLastError =
        kernel.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
      'GetLastError',
    );
    final name = 'Global\\InternetMonitoringAgent_UCMS'.toNativeUtf16();
    final h = createMutexW(nullptr, 0, name);
    final err = getLastError();
    calloc.free(name);
    if (h == 0) return false;
    // ERROR_ALREADY_EXISTS = 183
    return err != 183;
  } catch (_) {
    return true;
  }
}

// === Linux: file lock ===
Future<bool> _unixLock() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final lockPath = p.join(dir.path, 'ima', 'agent.lock');
    final file = File(lockPath);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.lock(FileLock.exclusive);
      // Lockni ushlab turamiz — process tugashi bilan OS uni qo'yib yuboradi.
      // Bu yerda raf.close() chaqirilmaydi maxsus, lock yashashi uchun.
      return true;
    } catch (_) {
      await raf.close();
      return false;
    }
  } catch (_) {
    return true;
  }
}
