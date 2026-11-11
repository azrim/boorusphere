import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/drag_handle.dart';
import 'package:flutter/material.dart';

/// Opens a modal sheet built on [SheetShell].
Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // A sheet arrives from the edge it is pinned to and leaves the same way,
    // faster than it came. Reduced motion takes the travel to zero, which is
    // all this transition has: the framework moves the sheet by laying it out,
    // so there is no opacity leg to keep.
    sheetAnimationStyle: AnimationStyle(
      duration: context.motionDuration(DesignTokens.durationNormal),
      reverseDuration: context.motionDuration(DesignTokens.durationFast),
      curve: DesignTokens.curveStandard,
      reverseCurve: DesignTokens.curveAccelerate,
    ),
    builder: builder,
  );
}

/// The chrome every sheet in the app shares.
///
/// A drag handle, a title with its dismiss control, an optional tab strip, the
/// active panel and an optional pinned footer. The shell owns the height cap
/// and the system insets, so a panel only describes its own content.
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.title,
    this.tabs,
    this.child,
    this.footer,
    this.maxHeightFactor = 0.78,
  });

  final String title;

  /// A [SheetTabs] strip, placed directly under the title.
  final Widget? tabs;

  final Widget? child;
  final Widget? footer;

  /// Share of the screen height the sheet may take before its panel scrolls.
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.theme.textTheme;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // The cap has to be measured against the space the keyboard leaves
    // behind. Capping against the full screen would leave a sheet with a text
    // field only a sliver of body once the keyboard opens, since its header
    // and footer are still drawn at full size.
    final available = media.size.height - keyboard;

    return Padding(
      // A text field inside the sheet has to clear the keyboard.
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available * maxHeightFactor),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DragHandle(),
              Padding(
                padding: const EdgeInsets.only(
                  left: DesignTokens.spacingMd,
                  right: DesignTokens.spacingXs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: DesignTokens.iconAction,
                      ),
                      tooltip: context.t.dismiss,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              if (tabs case final tabs?) tabs,
              if (child case final child?) Flexible(child: child),
              if (footer case final footer?) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colorScheme.outlineVariant,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
                  child: footer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One label in a [SheetTabs] strip.
class SheetTab {
  const SheetTab(this.label, {this.count});

  final String label;

  /// A muted readout on the trailing edge, such as how many items the tab
  /// holds, so the size of a panel is known before it is opened.
  final String? count;
}

/// Segmented strip that puts one panel in front of the visitor at a time.
///
/// It sits directly under the title, inside thumb reach, and the active label
/// carries a hairline-thin underline so the strip reads as a divider that
/// happens to be tappable rather than as a second toolbar. Labels size to
/// their own text and the underline hugs the word, so a short label does not
/// leave a bar hanging under empty space.
///
/// The tabs share the strip's width instead of scrolling: the sheet already
/// owns the horizontal gesture for moving between panels, and a scrollable
/// strip would claim that gesture back on the line where the swipe starts.
class SheetTabs extends StatelessWidget {
  const SheetTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<SheetTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
      // The sheet's own surface is opaque, and the nearest Material above it
      // belongs to the page behind: without a transparent one here the tab's
      // ink would be painted under the sheet and never seen.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _SheetTabButton(
                  tab: tabs[i],
                  selected: i == index,
                  onTap: () => onChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetTabButton extends StatelessWidget {
  const _SheetTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final SheetTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final textTheme = context.theme.textTheme;
    final duration = context.motionDuration(DesignTokens.durationFast);
    final style = textTheme.labelLarge?.copyWith(
      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );

    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: DesignTokens.controlHeightMin,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth - DesignTokens.spacingCardInset * 2
                  : double.infinity;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  // The column takes the label's width, so the underline marks
                  // the word rather than the tab's third of the strip.
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: duration,
                              curve: DesignTokens.curveStandard,
                              style: style ?? const TextStyle(),
                              child: Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (tab.count case final count?) ...[
                              const SizedBox(width: DesignTokens.spacingXs + 2),
                              Text(
                                count,
                                maxLines: 1,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: duration,
                          curve: DesignTokens.curveStandard,
                          height: 2,
                          color: selected ? scheme.primary : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
