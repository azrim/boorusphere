import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/download_sidecar.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/data/repository/downloads/user_download_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../utils/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveContainer = HiveTestContainer();

  tearDownAll(hiveContainer.dispose);

  late Box<DownloadEntry> entryBox;
  late Box<DownloadProgress> progressBox;
  late Directory root;
  late UserDownloadsRepo repo;
  var nativeIds = <String>{};

  setUp(() async {
    entryBox = await Hive.openBox<DownloadEntry>(UserDownloadsRepo.entryKey);
    progressBox = await Hive.openBox<DownloadProgress>(
      UserDownloadsRepo.progressKey,
    );
    await entryBox.clear();
    await progressBox.clear();
    root = Directory.systemTemp.createTempSync('download_record_backup');
    nativeIds = <String>{};
    repo = UserDownloadsRepo(
      entryBox: entryBox,
      progressBox: progressBox,
      downloadDir: () async => root.path,
      nativeTaskIds: () async => nativeIds,
    );
  });

  tearDown(() async {
    await entryBox.clear();
    await progressBox.clear();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const post = Post(id: 42, serverId: 'Danbooru', tags: ['cat']);

  String payload({
    String id = 'task-1',
    String dest = 'Danbooru/42.jpg',
    String status = 'downloaded',
    int progress = 100,
    int timestamp = 123,
    int schema = UserDownloadsRepo.backupSchema,
  }) {
    return jsonEncode({
      'schema': schema,
      'entries': [
        {'id': id, 'post': post.toJson(), 'dest': dest},
      ],
      'progresses': [
        {
          'id': id,
          'status': status,
          'progress': progress,
          'timestamp': timestamp,
        },
      ],
    });
  }

  group('UserDownloadsRepo.export', () {
    test('carries the records, their statuses, and the schema', () async {
      await entryBox.put(
        'task-1',
        const DownloadEntry(id: 'task-1', post: post, dest: 'Danbooru/42.jpg'),
      );
      await progressBox.put(
        'task-1',
        const DownloadProgress(
          id: 'task-1',
          status: DownloadStatus.downloaded,
          progress: 100,
          timestamp: 123,
        ),
      );

      final exported = await repo.export();
      final data = exported.value as Map;

      expect(exported.key, UserDownloadsRepo.entryKey);
      expect(data['schema'], UserDownloadsRepo.backupSchema);
      final entries = data['entries'] as List;
      expect(entries.single['id'], 'task-1');
      expect((entries.single['post'] as Map)['id'], 42);
      expect(entries.single['dest'], 'Danbooru/42.jpg');
      final progresses = data['progresses'] as List;
      expect(progresses.single, {
        'id': 'task-1',
        'status': 'downloaded',
        'progress': 100,
        'timestamp': 123,
      });
    });

    test('leaves the updater record out', () async {
      await entryBox.put(
        'apk',
        const DownloadEntry(
          id: 'apk',
          post: Post(id: -100),
          dest: 'update.apk',
        ),
      );
      await progressBox.put(
        'apk',
        const DownloadProgress(id: 'apk', status: DownloadStatus.downloaded),
      );

      final data = (await repo.export()).value as Map;

      expect(data['entries'], isEmpty);
      expect(data['progresses'], isEmpty);
    });
  });

  group('UserDownloadsRepo.import', () {
    test('keeps a missing file as a record that can be redownloaded', () async {
      await repo.import(payload());

      expect(entryBox.get('task-1')?.dest, 'Danbooru/42.jpg');
      final progress = progressBox.get('task-1');
      expect(progress?.status, DownloadStatus.downloaded);
      expect(progress?.progress, 100);
      expect(progress?.timestamp, 123);
      // Nothing is written to the metadata folder for a file that is absent.
      expect(
        File(downloadSidecarPath(root.path, 'Danbooru/42.jpg')).existsSync(),
        isFalse,
      );
    });

    test(
      'marks a record whose file is already present as downloaded',
      () async {
        final folder = Directory(p.join(root.path, 'Danbooru'))
          ..createSync(recursive: true);
        File(
          p.join(folder.path, '42.jpg'),
        ).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

        await repo.import(payload(status: 'failed', progress: 40));

        final progress = progressBox.get('task-1');
        expect(progress?.status, DownloadStatus.downloaded);
        expect(progress?.progress, 100);
        // The live completion path writes the sidecar too, so a restore keeps
        // the two sources of metadata in step.
        expect(
          File(downloadSidecarPath(root.path, 'Danbooru/42.jpg')).existsSync(),
          isTrue,
        );
      },
    );

    test('does not trust an in-flight status without a native task', () async {
      await repo.import(payload(status: 'downloading', progress: 34));

      final progress = progressBox.get('task-1');
      expect(progress?.status, DownloadStatus.failed);
      expect(progress?.progress, 34);
    });

    test('a file that exists but is not media becomes failed', () async {
      final folder = Directory(p.join(root.path, 'Danbooru'))
        ..createSync(recursive: true);
      File(p.join(folder.path, '42.jpg')).writeAsStringSync('<html></html>');

      await repo.import(payload());

      expect(progressBox.get('task-1')?.status, DownloadStatus.failed);
    });

    test('a record whose native task is alive is left alone', () async {
      nativeIds = {'task-1'};

      await repo.import(payload());

      expect(entryBox.isEmpty, isTrue);
      expect(progressBox.isEmpty, isTrue);
    });

    test('keeps local records the archive does not mention', () async {
      await entryBox.put(
        'local',
        const DownloadEntry(
          id: 'local',
          post: Post(id: 7, serverId: 'Danbooru'),
          dest: 'Danbooru/7.jpg',
        ),
      );

      await repo.import(payload());

      expect(entryBox.keys, containsAll(['local', 'task-1']));
    });

    test('refuses an unknown schema', () async {
      await entryBox.put(
        'local',
        const DownloadEntry(
          id: 'local',
          post: Post(id: 7, serverId: 'Danbooru'),
          dest: 'Danbooru/7.jpg',
        ),
      );

      await repo.import(payload(schema: UserDownloadsRepo.backupSchema + 1));

      expect(entryBox.keys, ['local']);
    });

    test('skips paths that could leave the download folder', () async {
      final data = jsonDecode(payload()) as Map<String, dynamic>;
      data['entries'] = [
        for (final dest in ['/data/local/tmp/a.jpg', '../a.jpg', '.metadata/a'])
          {'id': dest, 'post': post.toJson(), 'dest': dest},
      ];

      await repo.import(jsonEncode(data));

      expect(entryBox.isEmpty, isTrue);
    });

    test('reads a percent escape literally instead of decoding it', () async {
      final data = jsonDecode(payload()) as Map<String, dynamic>;
      data['entries'] = [
        {'id': 'task-1', 'post': post.toJson(), 'dest': '%2e%2e/a.jpg'},
      ];

      await repo.import(jsonEncode(data));

      // Every reader joins this path as one name under the download folder;
      // decoding it here is what would turn it into a parent hop.
      expect(entryBox.get('task-1')?.dest, '%2e%2e/a.jpg');
    });

    test('a malformed archive leaves the stored records intact', () async {
      await entryBox.put(
        'local',
        const DownloadEntry(
          id: 'local',
          post: Post(id: 7, serverId: 'Danbooru'),
          dest: 'Danbooru/7.jpg',
        ),
      );

      await repo.import(
        jsonEncode({
          'schema': UserDownloadsRepo.backupSchema,
          'entries': [
            {
              'id': 'broken',
              'post': {'id': 'not-a-number'},
              'dest': 'a.jpg',
            },
          ],
        }),
      );

      expect(entryBox.keys, ['local']);
    });
  });
}
