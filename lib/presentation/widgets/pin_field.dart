import 'dart:async';

import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A numeric PIN entry.
///
/// Obscured and digits-only: the value is a short number the user will type
/// again on the lock screen, so the field hides it from onlookers and gives
/// the keyboard no row to suggest anything else from.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.autofocus = false,
    this.enabled = true,
    this.errorText,
    this.maxLength = 8,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool autofocus;
  final bool enabled;
  final String? errorText;
  final int maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final decoration = flatFieldDecoration(
      context,
      label: label,
      hint: hint,
    ).copyWith(errorText: errorText, counterText: '');

    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ],
      style: textTheme.titleMedium?.copyWith(letterSpacing: 4),
      decoration: decoration,
      onSubmitted: onSubmitted,
    );
  }
}

/// The wait between PIN attempts, kept live on screen.
///
/// The timer only drives this line; the lock state clears [retryAt] when the
/// wait is over, which rebuilds the field into its enabled state.
class PinRetryCountdown extends StatefulWidget {
  const PinRetryCountdown({
    super.key,
    required this.retryAt,
    required this.secondsLabel,
  });

  final DateTime retryAt;

  /// Builds the line for the whole seconds left, rounded up.
  final String Function(int seconds) secondsLabel;

  @override
  State<PinRetryCountdown> createState() => _PinRetryCountdownState();
}

class _PinRetryCountdownState extends State<PinRetryCountdown> {
  late final Timer _timer;
  var _seconds = 0;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void didUpdateWidget(PinRetryCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final left = widget.retryAt.difference(DateTime.now()).inMilliseconds;
    final seconds = left <= 0 ? 0 : (left / 1000).ceil();
    if (!mounted || seconds == _seconds) return;
    setState(() => _seconds = seconds);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.secondsLabel(_seconds),
      style: context.theme.textTheme.bodySmall?.copyWith(
        color: context.colorScheme.error,
      ),
    );
  }
}

/// Spacing between the field and the line under it.
const pinMessageGap = SizedBox(height: DesignTokens.spacingSm);
