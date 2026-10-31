import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';

/// Folder, relative to the shared download folder, that a new file for [post]
/// belongs in.
///
/// Empty when grouping is off, so the file sits in the shared root next to the
/// files downloaded before this setting existed. An unknown server id still
/// gives a folder of its own: its name is all the app has left after the server
/// was deleted.
String downloadFolderOf(
  Post post, {
  required Iterable<Server> servers,
  required bool groupByServer,
}) {
  if (!groupByServer) return '';

  var name = post.serverId;
  for (final server in servers) {
    if (server.id == post.serverId) {
      name = server.name;
      break;
    }
  }
  return sanitizeFolderName(name);
}

/// [name] reduced to a single folder name the app can create and open.
///
/// Path separators and characters that file managers treat specially are
/// replaced, whitespace is collapsed, and leading dots are dropped: a folder
/// named `.` would point at the shared folder itself and `..` would point
/// outside it. A name that leaves nothing behind reports an empty string, which
/// callers read as "use the shared root".
String sanitizeFolderName(String name) {
  final replaced = name
      .replaceAll(RegExp(r'[\x00-\x1F\x7F/\\:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final withoutDots = replaced.replaceFirst(RegExp(r'^\.+'), '').trim();
  // One component of a path cannot exceed the filesystem's name limit, and a
  // server alias is user input: a runaway name would only make creation fail.
  if (withoutDots.length <= 100) return withoutDots;
  return withoutDots.substring(0, 100).trim();
}
