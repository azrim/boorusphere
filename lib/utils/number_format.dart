/// Compact count for chrome: `42`, `1.4k`, `12k`, `1.2M`.
///
/// Large booru counts are read at a glance, so the badge keeps them short
/// instead of printing six digits that push the rest of the row aside.
String compactCount(int value) {
  final abs = value.abs();
  if (abs < 1000) return '$value';
  // 999,500 and up already rounds to a million, so it is written as one
  // instead of as "1000k".
  if (abs < 999500) {
    final scaled = value / 1000;
    return '${scaled.toStringAsFixed(abs < 10000 ? 1 : 0)}k';
  }
  return '${(value / 1000000).toStringAsFixed(1)}M';
}
