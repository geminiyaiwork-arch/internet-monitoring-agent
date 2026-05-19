import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../system_metrics_collector.dart';

// Windows-specific imports only loaded when on Windows
typedef _GetTickCountNative = Uint32 Function();
typedef _GetTickCountDart = int Function();

class WindowsMetrics {
  static int uptimeSeconds() {
    if (!Platform.isWindows) return 0;
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final getTickCount =
          kernel.lookupFunction<_GetTickCountNative, _GetTickCountDart>(
        'GetTickCount',
      );
      return getTickCount() ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  static ResourceSnapshot snapshot() {
    if (!Platform.isWindows) return ResourceSnapshot.empty;
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');

      // MEMORYSTATUSEX struct (manually, to avoid hard dep on win32 here)
      final memBuf = calloc<Uint8>(64);
      memBuf.cast<Uint32>().value = 64;
      final globalMemoryStatusEx = kernel.lookupFunction<
          Int32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)>('GlobalMemoryStatusEx');
      globalMemoryStatusEx(memBuf);
      final memLoad = (memBuf.cast<Uint32>() + 1).value;
      final totalPhys = (memBuf.cast<Uint64>() + 1).value;
      final availPhys = (memBuf.cast<Uint64>() + 2).value;
      calloc.free(memBuf);

      final freeBytes = calloc<Uint64>();
      final totalBytes = calloc<Uint64>();
      final totalFree = calloc<Uint64>();
      final root = 'C:\\'.toNativeUtf16();
      final getDiskFreeSpaceEx = kernel.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
              Pointer<Uint64>),
          int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
              Pointer<Uint64>)>('GetDiskFreeSpaceExW');
      getDiskFreeSpaceEx(root, freeBytes, totalBytes, totalFree);
      final diskTotal = totalBytes.value;
      final diskFree = freeBytes.value;
      calloc.free(root);
      calloc.free(freeBytes);
      calloc.free(totalBytes);
      calloc.free(totalFree);

      final ramTotalMb = (totalPhys ~/ (1024 * 1024)).clamp(1, 1 << 20);
      final ramAvailMb = (availPhys ~/ (1024 * 1024)).clamp(0, ramTotalMb);
      final ramUsedMb = (ramTotalMb - ramAvailMb).clamp(0, ramTotalMb);
      final diskTotalMb = (diskTotal ~/ (1024 * 1024)).clamp(1, 1 << 30);
      final diskFreeMb = (diskFree ~/ (1024 * 1024)).clamp(0, diskTotalMb);
      return ResourceSnapshot(
        ramTotalMb: ramTotalMb,
        ramUsedMb: ramUsedMb,
        diskTotalMb: diskTotalMb,
        diskFreeMb: diskFreeMb,
        cpuUsagePercent: memLoad.clamp(0, 100),
      );
    } catch (_) {
      return ResourceSnapshot.empty;
    }
  }
}
