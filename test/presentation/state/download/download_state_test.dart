import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/downloads_repo.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// In-memory [DownloadsRepo] that records the order of its writes and can drop
/// one of them, which is how a process death between two boxes is replayed.
class _FakeDownloadsRepo implements DownloadsRepo {
  _FakeDownloadsRepo(Iterable<DownloadEntry> entries)
    : _entries = {for (final entry in entries) entry.id: entry};

  final Map<String, DownloadEntry> _entries;
  final Map<String, DownloadProgress> _progresses = {};

  /// Labels of the writes that were reached, in order.
  final List<String> writes = [];

  /// 1-based index of the write that never lands.
  int? abortAtWrite;

  Future<void> _write(String label) async {
    writes.add(label);
    if (writes.length == abortAtWrite) {
      throw StateError('process death');
    }
  }

  @override
  Future<void> addEntry(DownloadEntry entry) async {
    await _write('add:${entry.id}');
    _entries[entry.id] = entry;
  }

  @override
  Future<void> removeEntry(String id) async {
    await _write('remove:$id');
    _entries.remove(id);
  }

  @override
  Future<void> updateProgress(DownloadProgress progress) async {
    await _write('progress:${progress.id}');
    _progresses[progress.id] = progress;
  }

  @override
  Future<void> removeProgress(String id) async {
    await _write('unprogress:$id');
    _progresses.remove(id);
  }

  @override
  Future<void> clearEntries() async {
    _entries.clear();
  }

  @override
  Future<void> clearProgresses() async {
    _progresses.clear();
  }

  @override
  Iterable<DownloadEntry> getEntries() => _entries.values;

  @override
  Iterable<DownloadProgress> getProgresses() => _progresses.values;

  bool hasEntry(String id) => _entries.containsKey(id);
}

void main() {
  const oldEntry = DownloadEntry(id: 'old', dest: 'a.jpg');

  late _FakeDownloadsRepo repo;
  late ProviderContainer container;

  DownloadEntryState notifier() =>
      container.read(downloadEntryStateProvider.notifier);

  setUp(() {
    repo = _FakeDownloadsRepo([oldEntry]);
    container = ProviderContainer(
      overrides: [downloadsRepoProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  group('DownloadEntryState.add', () {
    test('publishes the record before the box write', () async {
      const entry = DownloadEntry(id: 'new', dest: 'b.jpg');

      final pending = notifier().add(entry);

      // A completion event arriving during the write has to find the entry.
      expect(container.read(downloadEntryStateProvider).map((it) => it.id), [
        'old',
        'new',
      ]);

      await pending;
      expect(repo.hasEntry('new'), isTrue);
    });
  });

  group('DownloadEntryState.update', () {
    test('writes the replacement before dropping the old record', () async {
      await notifier().update('old', oldEntry.copyWith(id: 'new'));

      expect(repo.writes, ['add:new', 'remove:old']);
      expect(repo.hasEntry('new'), isTrue);
      expect(repo.hasEntry('old'), isFalse);
      expect(container.read(downloadEntryStateProvider).map((it) => it.id), [
        'new',
      ]);
    });

    test('a death between the writes keeps a record for the new task', () async {
      repo.abortAtWrite = 2;

      await expectLater(
        notifier().update('old', oldEntry.copyWith(id: 'new')),
        throwsStateError,
      );

      // The stale row survives as a duplicate the boot reconciliation settles;
      // the running task never loses its record.
      expect(repo.hasEntry('new'), isTrue);
    });

    test('updating an entry in place keeps it', () async {
      await notifier().update('old', oldEntry.copyWith(dest: 'b.jpg'));

      expect(repo.writes, ['add:old']);
      expect(repo.hasEntry('old'), isTrue);
      expect(container.read(downloadEntryStateProvider).single.dest, 'b.jpg');
    });
  });
}
