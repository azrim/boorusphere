enum GestureType {
  swipeUp,
  swipeDown,
  swipeLeft,
  swipeRight,
  doubleTap,
  longPress,
  tap,
}

class GestureConfig {
  const GestureConfig({
    this.swipeUp,
    this.swipeDown,
    this.swipeLeft,
    this.swipeRight,
    this.doubleTap,
    this.longPress,
    this.tap,
  });

  const GestureConfig.undefined()
      : swipeUp = null,
        swipeDown = null,
        swipeLeft = null,
        swipeRight = null,
        doubleTap = null,
        longPress = null,
        tap = null;

  factory GestureConfig.fromJson(Map<String, dynamic> json) {
    return GestureConfig(
      swipeUp: json['swipeUp'] as String?,
      swipeDown: json['swipeDown'] as String?,
      swipeLeft: json['swipeLeft'] as String?,
      swipeRight: json['swipeRight'] as String?,
      doubleTap: json['doubleTap'] as String?,
      longPress: json['longPress'] as String?,
      tap: json['tap'] as String?,
    );
  }

  final String? swipeUp;
  final String? swipeDown;
  final String? swipeLeft;
  final String? swipeRight;
  final String? doubleTap;
  final String? longPress;
  final String? tap;

  GestureConfig copyWith({
    String? Function()? swipeUp,
    String? Function()? swipeDown,
    String? Function()? swipeLeft,
    String? Function()? swipeRight,
    String? Function()? doubleTap,
    String? Function()? longPress,
    String? Function()? tap,
  }) {
    return GestureConfig(
      swipeUp: swipeUp != null ? swipeUp() : this.swipeUp,
      swipeDown: swipeDown != null ? swipeDown() : this.swipeDown,
      swipeLeft: swipeLeft != null ? swipeLeft() : this.swipeLeft,
      swipeRight: swipeRight != null ? swipeRight() : this.swipeRight,
      doubleTap: doubleTap != null ? doubleTap() : this.doubleTap,
      longPress: longPress != null ? longPress() : this.longPress,
      tap: tap != null ? tap() : this.tap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (swipeUp != null) 'swipeUp': swipeUp,
      if (swipeDown != null) 'swipeDown': swipeDown,
      if (swipeLeft != null) 'swipeLeft': swipeRight,
      if (swipeRight != null) 'swipeRight': swipeRight,
      if (doubleTap != null) 'doubleTap': doubleTap,
      if (longPress != null) 'longPress': longPress,
      if (tap != null) 'tap': tap,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureConfig &&
          runtimeType == other.runtimeType &&
          swipeUp == other.swipeUp &&
          swipeDown == other.swipeDown &&
          swipeLeft == other.swipeLeft &&
          swipeRight == other.swipeRight &&
          doubleTap == other.doubleTap &&
          longPress == other.longPress &&
          tap == other.tap;

  @override
  int get hashCode =>
      swipeUp.hashCode ^
      swipeDown.hashCode ^
      swipeLeft.hashCode ^
      swipeRight.hashCode ^
      doubleTap.hashCode ^
      longPress.hashCode ^
      tap.hashCode;
}

extension GestureConfigExtensions on GestureConfig? {
  bool canHandleGesture(GestureType gesture) {
    final gestures = this;
    if (gestures == null) return false;

    return switch (gesture) {
      GestureType.swipeDown => gestures.swipeDown != null,
      GestureType.swipeUp => gestures.swipeUp != null,
      GestureType.swipeLeft => gestures.swipeLeft != null,
      GestureType.swipeRight => gestures.swipeRight != null,
      GestureType.doubleTap => gestures.doubleTap != null,
      GestureType.longPress => gestures.longPress != null,
      GestureType.tap => gestures.tap != null,
    };
  }

  bool get canLongPress => canHandleGesture(GestureType.longPress);
  bool get canDoubleTap => canHandleGesture(GestureType.doubleTap);
  bool get canTap => canHandleGesture(GestureType.tap);
  bool get canSwipeDown => canHandleGesture(GestureType.swipeDown);
  bool get canSwipeUp => canHandleGesture(GestureType.swipeUp);
  bool get canSwipeLeft => canHandleGesture(GestureType.swipeLeft);
  bool get canSwipeRight => canHandleGesture(GestureType.swipeRight);
}
