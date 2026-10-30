import 'package:boorusphere/presentation/theme/app_surfaces.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Bottom chrome a toast has to clear.
///
/// The home page publishes the measured height of its search bar here, so a
/// message lands above the bar instead of over the field.
class ToastInset extends InheritedWidget {
  const ToastInset({super.key, required this.bottom, required super.child});

  final double bottom;

  /// The space the toast keeps above itself, or zero on a screen without
  /// bottom chrome.
  static double of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ToastInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ToastInset oldWidget) => oldWidget.bottom != bottom;
}

/// Shows [message] as one of the app's toasts.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = DesignTokens.durationSnackbar,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showToastOn(
    messenger,
    message,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
    bottomInset: ToastInset.of(context),
  );
}

/// The same toast for a messenger reached through a key: the boot failure is
/// reported from the root, which has no `ScaffoldMessenger` above it.
void showToastOn(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = DesignTokens.durationSnackbar,
  double bottomInset = 0,
}) {
  messenger.showSnackBar(
    buildAppToast(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      bottomInset: bottomInset,
    ),
  );
}

/// A floating card rather than a strip: a toast is a note laid over the
/// screen, so it keeps a margin, rounds every corner and carries its own tone
/// instead of the scheme's loud container role.
@visibleForTesting
SnackBar buildAppToast({
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = DesignTokens.durationSnackbar,
  double bottomInset = 0,
}) {
  return SnackBar(
    content: _ToastCard(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    margin: EdgeInsets.fromLTRB(
      DesignTokens.spacingMd,
      0,
      DesignTokens.spacingMd,
      bottomInset + DesignTokens.spacingMd,
    ),
    duration: duration,
    // Swipe the note away; tapping the action also dismisses it.
    dismissDirection: DismissDirection.down,
    shape: const RoundedRectangleBorder(),
  );
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message, this.actionLabel, this.onAction});

  /// Toasts stay a readable measure on a tablet instead of stretching into a
  /// banner.
  static const _maxWidth = 560.0;

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final flat = AppSurfacePolicy.of(context).flat;
    final action = actionLabel;

    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Material(
          // Midnight keeps its flat black surfaces with a hairline; every
          // other theme lifts the card one tone above the page.
          color: flat ? Colors.black : scheme.surfaceContainerHigh,
          elevation: flat ? 0 : DesignTokens.elevationFloating,
          shadowColor: DesignTokens.shadowColor(scheme),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.controlHeightMin,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: DesignTokens.spacingMd,
                right: action == null
                    ? DesignTokens.spacingMd
                    : DesignTokens.spacingSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spacingSm,
                      ),
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: DesignTokens.spacingSm),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        minimumSize: const Size(
                          DesignTokens.controlHeightMin,
                          DesignTokens.controlHeightMin,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingSm,
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.maybeOf(
                          context,
                        )?.hideCurrentSnackBar();
                        onAction?.call();
                      },
                      child: Text(action),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
