enum SwipeMode {
  horizontal,
  vertical;

  factory SwipeMode.parse(value) => switch (value) {
        'horizontal' || '0' || 0 => horizontal,
        'vertical' || '1' || 1 => vertical,
        _ => defaultValue,
      };

  static const SwipeMode defaultValue = horizontal;

  dynamic toData() => index;

  String get name => switch (this) {
        SwipeMode.horizontal => 'horizontal',
        SwipeMode.vertical => 'vertical',
      };
}
