import 'dart:io';

import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shared_storage_handle.g.dart';

@Riverpod(keepAlive: true)
SharedStorageHandle sharedStorageHandle(Ref ref) {
  throw UnimplementedError();
}

Future<SharedStorageHandle> provideSharedStorageHandle() async {
  final downloadPath = await StorageUtil().getDownloadPath();
  return SharedStorageHandle(downloadPath: downloadPath);
}

class SharedStorageHandle {
  SharedStorageHandle({required this.downloadPath});

  final String downloadPath;

  String get path {
    return p.join(downloadPath, 'Boorusphere');
  }

  File get _nomedia {
    return File(p.join(path, '.nomedia'));
  }

  bool get isHidden {
    return _nomedia.existsSync();
  }

  Future<void> init() async {
    await Permission.storage.request();
    final dir = Directory(path);
    if (!dir.existsSync()) {
      try {
        Directory(path).createSync();
      } catch (e) {
        mainLog.e('SharedStorageHandle: Failed to create dir', e);
      }
    }
  }

  Directory createSubDir(String directory) {
    final dir = Directory(p.join(path, directory));
    try {
      dir.createSync();
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to create subdir $directory', e);
    }
    return dir;
  }

  bool fileExists(String relativePath) {
    final file = File(p.join(path, Uri.decodeFull(relativePath)));
    try {
      return file.existsSync();
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to check file $relativePath', e);
      return false;
    }
  }

  Future<void> rescan() async {
    await MediaScanner.loadMedia(path: path);
  }

  Future<void> hide(bool hide) async {
    await init();
    final isExists = _nomedia.existsSync();
    try {
      if (hide && !isExists) {
        await _nomedia.create();
      } else if (!hide && isExists) {
        await _nomedia.delete();
      }
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to toggle .nomedia', e);
    }
    await rescan();
  }

  Future<void> open(String dest, {String? on}) async {
    try {
      final filePath = p.join(on ?? path, Uri.decodeFull(dest));
      await StorageUtil().open(filePath);
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to open $dest', e);
    }
  }
}
