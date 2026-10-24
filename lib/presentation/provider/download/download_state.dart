import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
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

  Future<void> add(DownloadEntry entry) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.addEntry(entry);
    state = [...state.where((it) => it.id != entry.id), entry];
  }

  Future<void> remove(String id) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.removeEntry(id);
    await ref.read(downloadProgressStateProvider.notifier).remove(id);
    state = [...state.where((it) => it.id != id)];
  }

  Future<void> update(String id, DownloadEntry entry) async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.removeEntry(id);
    await repo.addEntry(entry);
    state = [...state.where((it) => it.id != id), entry];
  }

  Future<void> clear() async {
    final repo = ref.read(downloadsRepoProvider);
    await repo.clearEntries();
    await ref.read(downloadProgressStateProvider.notifier).clear();
    state = [];
  }
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

  /// Newest entry for [post].
  ///
  /// Retrying or switching quality appends a new entry instead of reusing the
  /// old one, so the first match would keep reporting a state the running
  /// download has already left behind.
  DownloadEntry getByPost(Post post) {
    var found = DownloadEntry.empty;
    for (final entry in this) {
      if (entry.post.id == post.id && entry.post.serverId == post.serverId) {
        found = entry;
      }
    }
    return found;
  }
}
