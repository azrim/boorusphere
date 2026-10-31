import 'dart:io';

import 'package:boorusphere/pigeon/storage_util.pi.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:boorusphere/utils/media_file.dart';
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

  bool _permissionRequested = false;

  String get path {
    return p.join(downloadPath, 'Boorusphere');
  }

  File get _nomedia {
    return File(p.join(path, '.nomedia'));
  }

  bool get isHidden {
    return _nomedia.existsSync();
  }

  /// Makes sure the shared folder exists and reports whether it is usable.
  ///
  /// [Permission.storage] maps to `READ/WRITE_EXTERNAL_STORAGE`, which the
  /// manifest caps at API 32/29, so the request cannot be granted on newer
  /// Android releases. It is still asked for where it applies, and only once
  /// per session: [init] runs twice on a cache miss while the answer cannot
  /// change in between. The folder check below is what decides, since a denied
  /// permission does not by itself mean the path is unwritable.
  Future<bool> init() async {
    if (!_permissionRequested) {
      _permissionRequested = true;
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        mainLog.w('SharedStorageHandle: storage permission not granted');
      }
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        mainLog.e('SharedStorageHandle: Failed to create dir', e);
      }
    }
    return dir.existsSync();
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
    try {
      final file = File(p.join(path, decodeComponentSafely(relativePath)));
      return file.existsSync();
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to check file $relativePath', e);
      return false;
    }
  }

  /// Whether [dest] points at a non-empty file whose head matches a media
  /// container this app writes.
  ///
  /// [dest] is resolved like [fileExists] resolves it, while an absolute path
  /// is taken as-is so the temporary folder of an archived batch can be
  /// checked as well. The check stays lenient on purpose: bytes of a known
  /// container pass whatever the extension says, and an extension that is not
  /// a media one passes unless the head is plainly markup. What it rejects is
  /// the empty file and the HTML page a hotlink-protected booru sends in place
  /// of the image.
  bool isValidMedia(String dest) {
    try {
      return isMediaFile(_resolveFile(dest));
    } catch (e) {
      mainLog.e('SharedStorageHandle: Failed to validate $dest', e);
      return false;
    }
  }

  /// Asks the platform to scan the download folder.
  ///
  /// The scanner takes files, so this only refreshes the folder entry itself:
  /// a file that has to show up in the gallery goes through [rescanFile].
  Future<void> rescan() async {
    await StorageUtil().scanMedia(path);
  }

  /// Indexes the file at [dest] into the platform media database.
  ///
  /// A file written into the folder stays out of the gallery and the media
  /// pickers until the system scans it by path.
  Future<void> rescanFile(String dest) async {
    await StorageUtil().scanMedia(_resolveFile(dest).path);
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

  File _resolveFile(String dest) {
    if (p.isAbsolute(dest)) return File(dest);
    return File(p.join(path, decodeComponentSafely(dest)));
  }
}
