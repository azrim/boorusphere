import 'dart:io';

import 'package:path/path.dart' as path;

/// The name of every archive this app writes to the backups folder.
const String archiveAppId = 'boorusphere';

/// The folder only ever holds what this prefix names, and pruning deletes from
/// it, so the prefix is the one rule both the writer and the reaper read.
const String archivePrefix = '${archiveAppId}_backup_';

/// How many archives one timestamped second can hold before the writer gives
/// up rather than overwrite. Reaching it would mean a hundred backup runs in
/// the same second.
const int archiveMaxSequence = 99;

/// The name of the [sequence]-th archive of the second [stamp] names.
///
/// The counter is fixed width and sits before the extension. Both halves
/// matter: the pruning step reads the age of an archive out of its name with a
/// plain string sort, so the timestamp has to keep deciding the order.
String archiveName(String stamp, String extension, {int sequence = 0}) {
  final suffix = sequence.toString().padLeft(2, '0');
  return '$archivePrefix$stamp-$suffix.$extension';
}

/// Whether [name] is an archive this app wrote, and therefore fair game for
/// pruning. A file the user dropped into the folder is not.
bool isArchiveName(String name) {
  return RegExp('^$archivePrefix.+\\.(zip|enc)\$').hasMatch(name);
}

/// The first archive name for [stamp] that [dir] does not already hold.
///
/// Returning a path that does not exist yet is the point: two runs landing in
/// the same second used to delete the archive that was already there, and the
/// folder ended up holding whichever run finished last.
File freeArchiveFile(Directory dir, String stamp, String extension) {
  for (var sequence = 0; sequence <= archiveMaxSequence; sequence++) {
    final candidate = File(
      path.join(dir.path, archiveName(stamp, extension, sequence: sequence)),
    );
    if (!candidate.existsSync()) return candidate;
  }
  throw StateError('the backups folder holds no free name for $stamp');
}
