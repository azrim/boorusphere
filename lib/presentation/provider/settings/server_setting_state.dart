import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/server_setting.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_setting_state.g.dart';

@riverpod
class ServerSettingState extends _$ServerSettingState {
  /// The post counts the settings offer, and the only values a stored limit
  /// may take. The picker asserts that its value is one of the items it lists,
  /// so a count that arrives from an older or hand-edited archive — 250, or
  /// zero — has to snap to the nearest one rather than open a dropdown that
  /// cannot name it.
  static const postLimitChoices = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];

  static int postLimitFrom(int value) {
    var nearest = postLimitChoices.first;
    for (final choice in postLimitChoices) {
      if ((choice - value).abs() < (nearest - value).abs()) nearest = choice;
    }
    return nearest;
  }

  @override
  ServerSetting build() {
    final repo = ref.read(settingsRepoProvider);
    return ServerSetting(
      lastActiveId: repo.get(Setting.serverLastActiveId, or: ''),
      postLimit: postLimitFrom(
        repo.get(Setting.serverPostLimit, or: PageOption.defaultLimit),
      ),
      searchRating: repo.get(Setting.searchRating, or: BooruRating.safe),
    );
  }

  Future<void> setLastActiveId(String newId) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(lastActiveId: newId);
    await repo.put(Setting.serverLastActiveId, newId);
  }

  Future<void> setPostLimit(int value) async {
    final repo = ref.read(settingsRepoProvider);
    final limit = postLimitFrom(value);
    state = state.copyWith(postLimit: limit);
    await repo.put(Setting.serverPostLimit, limit);
  }

  Future<void> setRating(BooruRating value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(searchRating: value);
    await repo.put(Setting.searchRating, value);
  }
}
