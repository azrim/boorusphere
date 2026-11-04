import 'dart:io';

import 'package:boorusphere/presentation/provider/data_backup/archive_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('archive_name');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('archiveName', () {
    test('the second archive of a second gets its own name', () {
      expect(
        archiveName('2026-11-04-10-00-00', 'zip'),
        isNot(archiveName('2026-11-04-10-00-00', 'zip', sequence: 1)),
      );
      expect(
        archiveName('2026-11-04-10-00-00', 'enc'),
        'boorusphere_backup_2026-11-04-10-00-00-00.enc',
      );
    });

    test('the counter is fixed width so the timestamp keeps sorting', () {
      final names = List.generate(
        12,
        (it) => archiveName('2026-11-04-10-00-00', 'zip', sequence: it),
      );
      final sorted = [...names]..sort();

      expect(sorted, names);
      expect(p.basename(names[10]), endsWith('-10.zip'));
    });

    test('a later second outranks every archive of the earlier one', () {
      final older = archiveName('2026-11-03-23-59-59', 'zip', sequence: 99);
      final newer = archiveName('2026-11-04-00-00-00', 'zip');
      // What pruning relies on: newest first, read off the name alone.
      final sorted = [older, newer]..sort((a, b) => b.compareTo(a));

      expect(sorted.first, newer);
    });
  });

  group('isArchiveName', () {
    test('matches what the writer names, both envelopes', () {
      expect(
        isArchiveName(p.basename(archiveName('2026-11-04-10-00-00', 'zip'))),
        isTrue,
      );
      expect(
        isArchiveName(
          p.basename(archiveName('2026-11-04-10-00-00', 'enc', sequence: 7)),
        ),
        isTrue,
      );
    });

    test('leaves files the app did not write alone', () {
      expect(isArchiveName('notes.txt'), isFalse);
      expect(
        isArchiveName('boorusphere_backup_2026-11-04-00-00-00-00.tar'),
        isFalse,
      );
      expect(isArchiveName('boorusphere_2026-11-04-00-00-00.zip'), isFalse);
    });
  });

  group('freeArchiveFile', () {
    test('does not hand out a name that is already taken', () {
      final first = freeArchiveFile(tempDir, '2026-11-04-10-00-00', 'zip')
        ..writeAsStringSync('first');
      final second = freeArchiveFile(tempDir, '2026-11-04-10-00-00', 'zip');

      expect(second.path, isNot(first.path));
      // The regression this pins: the folder used to keep only whichever run
      // finished last, because the second one deleted the first archive.
      expect(File(first.path).readAsStringSync(), 'first');
    });

    test('each second starts its own counter', () {
      freeArchiveFile(
        tempDir,
        '2026-11-04-10-00-00',
        'zip',
      ).writeAsStringSync('a');

      final other = freeArchiveFile(tempDir, '2026-11-04-10-00-01', 'zip');

      expect(p.basename(other.path), endsWith('-00.zip'));
    });

    test('gives up rather than overwrite a full second', () {
      for (var sequence = 0; sequence <= archiveMaxSequence; sequence++) {
        File(
          p.join(
            tempDir.path,
            archiveName('2026-11-04-10-00-00', 'zip', sequence: sequence),
          ),
        ).createSync();
      }

      expect(
        () => freeArchiveFile(tempDir, '2026-11-04-10-00-00', 'zip'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
