import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:boorusphere/presentation/widgets/styled_overlay_region.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class GestureSettingsPage extends ConsumerWidget {
  const GestureSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gestureSettings = ref.watch(gestureSettingStateNotifierProvider);
    final gestureNotifier = ref.read(
      gestureSettingStateNotifierProvider.notifier,
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.t.settingsPage.gestureSettings)),
      body: StyledOverlayRegion(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
            ),
            children: [
              SettingsSection(
                title: context.t.settingsPage.swipeMode,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spacingCardInset,
                      0,
                      DesignTokens.spacingCardInset,
                      DesignTokens.spacingSm,
                    ),
                    child: Text(
                      context.t.settingsPage.swipeModeDesc,
                      style: context.theme.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  RadioGroup<SwipeMode>(
                    groupValue: gestureSettings.swipeMode,
                    onChanged: (value) {
                      if (value != null) {
                        gestureNotifier.updateSwipeMode(value);
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<SwipeMode>(
                          value: SwipeMode.horizontal,
                          title: Text(context.t.settingsPage.horizontal),
                          subtitle: Text(context.t.settingsPage.horizontalDesc),
                          secondary: const Icon(Icons.swap_horiz),
                        ),
                        RadioListTile<SwipeMode>(
                          value: SwipeMode.vertical,
                          title: Text(context.t.settingsPage.vertical),
                          subtitle: Text(context.t.settingsPage.verticalDesc),
                          secondary: const Icon(Icons.swap_vert),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: context.t.settingsPage.swipeActions,
                children: [
                  SwitchListTile(
                    title: Text(context.t.settingsPage.swipeToDetails),
                    subtitle: Text(context.t.settingsPage.swipeToDetailsDesc),
                    value: gestureSettings.enableSwipeToDetails,
                    onChanged: (_) => gestureNotifier.toggleSwipeToDetails(),
                  ),
                  SwitchListTile(
                    title: Text(context.t.settingsPage.swipeToDismiss),
                    subtitle: Text(context.t.settingsPage.swipeToDismissDesc),
                    value: gestureSettings.enableSwipeToDismiss,
                    onChanged: (_) => gestureNotifier.toggleSwipeToDismiss(),
                  ),
                ],
              ),
              SettingsSection(
                title: context.t.settingsPage.sensitivity,
                children: [
                  SettingsSliderTile(
                    title: context.t.settingsPage.swipeDownThreshold,
                    value: gestureSettings.swipeDownThreshold,
                    min: 50,
                    max: 200,
                    divisions: 15,
                    helper: context.t.settingsPage.swipeDownThresholdDesc(
                      threshold: gestureSettings.swipeDownThreshold.round(),
                    ),
                    onChanged: gestureNotifier.updateSwipeDownThreshold,
                  ),
                ],
              ),
              SettingsSection(
                title: context.t.settingsPage.reset,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spacingCardInset,
                      DesignTokens.spacingSm,
                      DesignTokens.spacingCardInset,
                      DesignTokens.spacingMd,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: () {
                          gestureNotifier.reset();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.t.settingsPage.resetSuccess,
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text(context.t.resetToDefault),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
