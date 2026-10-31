import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Folder inside the shared download folder that holds the metadata files.
///
/// The name starts with a dot so file managers and the media scanner leave it
/// alone; the `.nomedia` marker in the shared root covers it as well.
const downloadMetadataDir = '.metadata';

/// JSON payload written next to a finished file.
///
/// The schema number lets a later reader tell the shape apart before trusting
/// the rest. Only the post and the download itself are stored: the file URL
/// can carry a token for some engines, and a metadata file must not keep one.
Map<String, Object?> downloadSidecarJson(
  DownloadEntry entry, {
  required DateTime downloadedAt,
}) {
  return {
    'schema': 1,
    'downloadedAt': downloadedAt.millisecondsSinceEpoch,
    'entryId': entry.id,
    'dest': entry.dest,
    'post': entry.post.toJson(),
  };
}

/// Metadata path for the file at [dest] below the shared [root].
///
/// The media path is mirrored, so `Danbooru/123.jpg` keeps its metadata at
/// `.metadata/Danbooru/123.jpg.json` and a reader can find it without an
/// index.
String downloadSidecarPath(String root, String dest) {
  // [dest] keeps the separators of the stored path; normalizing it keeps the
  // metadata path identical on every platform the tests run on.
  return p.join(root, downloadMetadataDir, '${p.normalize(dest)}.json');
}

/// Writes the metadata for [entry], replacing an earlier one.
///
/// Best effort: a metadata file the app cannot write must not turn a finished
/// download into a failed one. The updater APK lives in the cache folder and is
/// skipped, like every other app-owned entry.
Future<void> writeDownloadSidecar({
  required String root,
  required DownloadEntry entry,
}) async {
  if (entry.dest.isEmpty || entry.post.isReserved) return;

  try {
    final file = File(downloadSidecarPath(root, entry.dest));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(downloadSidecarJson(entry, downloadedAt: DateTime.now())),
    );
  } catch (e, stack) {
    mainLog.e(
      'Downloads: failed to write metadata for ${entry.dest}',
      e,
      stack,
    );
  }
}

/// Removes the metadata of [dest], if one was written.
///
/// Called when the media file itself is deleted. Forgetting an entry without
/// its file keeps the metadata, since the record can still be redownloaded.
Future<void> deleteDownloadSidecar({
  required String root,
  required String dest,
}) async {
  if (dest.isEmpty) return;

  try {
    final file = File(downloadSidecarPath(root, dest));
    if (file.existsSync()) await file.delete();
  } catch (e, stack) {
    mainLog.e('Downloads: failed to delete metadata for $dest', e, stack);
  }
}
