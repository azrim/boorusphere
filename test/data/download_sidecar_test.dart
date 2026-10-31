import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_sidecar.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('download_sidecar');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const entry = DownloadEntry(
    id: 'task-1',
    post: Post(id: 42, serverId: 'Danbooru', tags: ['foo']),
    dest: 'Danbooru/123.jpg',
  );

  test('paths mirror the media path inside the metadata folder', () {
    expect(
      downloadSidecarPath(root.path, entry.dest),
      p.join(root.path, '.metadata', 'Danbooru', '123.jpg.json'),
    );
  });

  test('a written sidecar carries the entry and its post', () async {
    await writeDownloadSidecar(root: root.path, entry: entry);

    final file = File(downloadSidecarPath(root.path, entry.dest));
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final post = json['post'] as Map<String, dynamic>;

    expect(json['schema'], 1);
    expect(json['entryId'], entry.id);
    expect(json['dest'], entry.dest);
    expect(json['downloadedAt'], isA<int>());
    expect(post['id'], 42);
    expect(post['serverId'], 'Danbooru');
    expect(post['tags'], ['foo']);
  });

  test('the updater entry gets no sidecar', () async {
    await writeDownloadSidecar(
      root: root.path,
      entry: const DownloadEntry(
        id: 'apk',
        post: Post.appReserved,
        dest: 'app.apk',
      ),
    );

    expect(
      File(downloadSidecarPath(root.path, 'app.apk')).existsSync(),
      isFalse,
    );
  });

  test('delete removes the sidecar and tolerates a missing one', () async {
    await writeDownloadSidecar(root: root.path, entry: entry);

    await deleteDownloadSidecar(root: root.path, dest: entry.dest);
    expect(
      File(downloadSidecarPath(root.path, entry.dest)).existsSync(),
      isFalse,
    );

    await deleteDownloadSidecar(root: root.path, dest: entry.dest);
  });

  test('an unwritable metadata folder does not throw', () async {
    final blocker = File(p.join(root.path, 'blocked'))
      ..writeAsStringSync('not a directory');

    await writeDownloadSidecar(root: blocker.path, entry: entry);
  });
}
