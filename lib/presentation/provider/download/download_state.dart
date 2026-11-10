import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download_state.g.dart';

@Riverpod(keepAlive: true)
class DownloadEntryState extends _$DownloadEntryState {
  @override
  List<DownloadEntry> build() {
    final repo = ref.read(downloadsRepoProvider);
    return repo.getEntries().toList();
  }

  /// Records [entry] and publishes it before the box write.
  ///
  /// A task can finish before its record lands, and the download completion
  /// callback drops an event it cannot find an entry for: publishing first
  /// keeps the record readable while the write is still in flight. A write
  /// that fails takes the record back out, so the in-memory list does not keep
  /// an entry the box never received.
  Future<void> add(DownloadEntry entry) async {
    final repo = ref.read(downloadsRepoProvider);
    state = [...state.where((it) => it.id != entry.id), entry];
    try {
      await repo.addEntry(entry);
    } catch (_) {
      state = [...state.where((it) => it.id != entry.id)];
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.removeEntry(id);
    await ref.read(downloadProgressStateProvider.notifier).remove(id);
    state = [...state.where((it) => it.id != id)];
  }

  Future<void> update(String id, DownloadEntry entry) async {
    final repo = ref.read(downloadsRepoProvider);
    // The replacement lands before the old record goes: the boxes are written
    // in separate frames, and a process death in between then leaves a
    // duplicate row the boot reconciliation can settle. The reverse order
    // would leave a running native task with no record at all.
    //
    // Update in-memory state synchronously first (with rollback on error) so
    // fast completion events arriving on ReceivePort find their entry.
    final prev = state;
    state = [...state.where((it) => it.id != id && it.id != entry.id), entry];
    try {
      await repo.addEntry(entry);
    } catch (_) {
      state = prev;
      rethrow;
    }
    if (id != entry.id) {
      await repo.removeEntry(id);
    }
    state = [...state.where((it) => it.id != id && it.id != entry.id), entry];
  }

  Future<void> clear() async {
    final repo = ref.read(downloadsRepoProvider);
    // The updater APK is kept by the repo, so its progress row has to stay as
    // well; clearing every row would leave the kept entry without a status.
    final kept = await repo.clearEntries();
    final progressState = ref.read(downloadProgressStateProvider.notifier);
    final dropped = ref
        .read(downloadProgressStateProvider)
        .where((it) => !kept.contains(it.id))
        .map((it) => it.id)
        .toList();
    for (final id in dropped) {
      try {
        await progressState.remove(id);
      } catch (e, stack) {
        // One row that cannot be removed must not keep the rest of the list
        // on screen after the entries are already gone.
        mainLog.e('Downloads: failed to drop the progress of $id', e, stack);
      }
    }
    state = repo.getEntries().toList();
  }
}

/// Bumped after the download folder gains or loses a file.
///
/// A row memoizes whether its file exists, otherwise every progress tick of a
/// running download would hit the disk for every entry; this is the signal that
/// tells the memoized rows to look again.
@Riverpod(keepAlive: true)
class DownloadFileRevision extends _$DownloadFileRevision {
  @override
  int build() => 0;

  void bump() => state++;
}

@Riverpod(keepAlive: true)
class DownloadProgressState extends _$DownloadProgressState {
  @override
  List<DownloadProgress> build() {
    final repo = ref.read(downloadsRepoProvider);
    return repo.getProgresses().toList();
  }

  Future<void> update(DownloadProgress progress) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.updateProgress(progress);
    state = [...state.where((it) => it.id != progress.id), progress];
  }

  Future<void> remove(String id) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.removeProgress(id);
    state = [...state.where((it) => it.id != id)];
  }

  Future<void> clear() async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.clearProgresses();
    state = [];
  }
}

extension DownloadProgressesExt on Iterable<DownloadProgress> {
  DownloadProgress getById(String id) {
    final item = firstWhereOrNull((x) => x.id == id);
    return item ?? DownloadProgress.none;
  }
}

extension DownloadEntriesExt on Iterable<DownloadEntry> {
  DownloadEntry getById(String id) {
    final item = firstWhereOrNull((x) => x.id == id);
    return item ?? DownloadEntry.empty;
  }

  Iterable<DownloadEntry> whereNotReserved() {
    return whereNot((x) => x.post.isReserved);
  }

  /// Entry for [post] a control should act on: a running one if any, the
  /// newest otherwise.
  ///
  /// Retrying or switching quality appends a new entry instead of reusing the
  /// old one, and after a restart the list is rebuilt from a box that iterates
  /// by id, not by age. The progress rows carry the timestamp, so the newest
  /// one wins; a running row beats a settled one because it is the entry the
  /// viewer still has to be able to cancel.
  DownloadEntry getByPost(
    Post post, {
    required DownloadProgress Function(String id) progressOf,
  }) {
    DownloadEntry newest = DownloadEntry.empty;
    DownloadEntry newestInFlight = DownloadEntry.empty;
    var newestAt = 0;
    var newestInFlightAt = 0;

    for (final entry in this) {
      if (entry.post.id != post.id || entry.post.serverId != post.serverId) {
        continue;
      }
      final progress = progressOf(entry.id);
      if (newest.id.isEmpty || progress.timestamp >= newestAt) {
        newest = entry;
        newestAt = progress.timestamp;
      }
      if (!progress.status.isDownloading && !progress.status.isPending) {
        continue;
      }
      if (newestInFlight.id.isEmpty || progress.timestamp >= newestInFlightAt) {
        newestInFlight = entry;
        newestInFlightAt = progress.timestamp;
      }
    }
    return newestInFlight.id.isEmpty ? newest : newestInFlight;
  }
}
