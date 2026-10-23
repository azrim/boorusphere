import 'dart:ui';

import 'package:flutter/material.dart';

/// Applies a backdrop blur, keeping one [ImageFilter] per parameter set so
/// the engine can reuse its cached raster instead of re-blurring on every
/// rebuild of the surrounding widget.
class BlurBackdrop extends StatefulWidget {
  const BlurBackdrop({
    super.key,
    required this.child,
    this.sigmaX = 0,
    this.sigmaY = 0,
    this.tileMode,
    this.blur = false,
  });

  final Widget child;
  final double sigmaX;
  final double sigmaY;
  final bool blur;
  final TileMode? tileMode;

  @override
  State<BlurBackdrop> createState() => _BlurBackdropState();
}

class _BlurBackdropState extends State<BlurBackdrop> {
  late ImageFilter _filter = _createFilter();

  ImageFilter _createFilter() {
    return ImageFilter.blur(
      sigmaX: widget.sigmaX,
      sigmaY: widget.sigmaY,
      tileMode: widget.tileMode,
    );
  }

  @override
  void didUpdateWidget(BlurBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sigmaX != widget.sigmaX ||
        oldWidget.sigmaY != widget.sigmaY ||
        oldWidget.tileMode != widget.tileMode) {
      _filter = _createFilter();
    }
  }

  @override
  Widget build(BuildContext context) {
    return !widget.blur
        ? widget.child
        : ClipRect(
            child: BackdropFilter(filter: _filter, child: widget.child),
          );
  }
}
