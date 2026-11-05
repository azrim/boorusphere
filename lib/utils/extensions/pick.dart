import 'package:boorusphere/utils/extensions/string.dart';
import 'package:deep_pick/deep_pick.dart';

extension PickExt on Pick {
  List<String> asStringList({String or = ''}) {
    return asListOrEmpty(
      (r) => r.asStringOrNull() ?? or,
    ).where((it) => it.isNotEmpty).toList();
  }

  List<String> toWordList({List<String> or = const <String>[]}) {
    return asStringOrNull()?.toWordList() ?? or;
  }

  /// A count, whether the site sent it as a number or as digits in a string.
  ///
  /// These engines disagree on the JSON type of the same field — a clone
  /// proxies `post_count` as `"12345"` where the site itself sends 12345 — and
  /// a count read from the wrong type silently becomes zero.
  int? asCountOrNull() {
    return switch (value) {
      final int it => it,
      final double it => it.toInt(),
      final String it => int.tryParse(it.trim()),
      _ => null,
    };
  }
}
