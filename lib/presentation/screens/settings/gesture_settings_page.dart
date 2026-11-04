import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/styled_overlay_region.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class GestureSettingsPage extends ConsumerWidget {
  const GestureSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gestureSettings = ref.watch(gestureSettingStateProvider);
    final gestureNotifier = ref.read(gestureSettingStateProvider.notifier);

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
                      style: AppTextRoles.of(context).rowSupporting,
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
                          subtitle: RowSubtitle(
                            Text(context.t.settingsPage.horizontalDesc),
                          ),
                          secondary: const Icon(Icons.swap_horiz),
                        ),
                        RadioListTile<SwipeMode>(
                          value: SwipeMode.vertical,
                          title: Text(context.t.settingsPage.vertical),
                          subtitle: RowSubtitle(
                            Text(context.t.settingsPage.verticalDesc),
                          ),
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
                    subtitle: RowSubtitle(
                      Text(context.t.settingsPage.swipeToDetailsDesc),
                    ),
                    value: gestureSettings.enableSwipeToDetails,
                    onChanged: (_) => gestureNotifier.toggleSwipeToDetails(),
                  ),
                  SwitchListTile(
                    title: Text(context.t.settingsPage.swipeToDismiss),
                    subtitle: RowSubtitle(
                      Text(context.t.settingsPage.swipeToDismissDesc),
                    ),
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
                    // The bounds come from the state, which clamps a stored
                    // threshold back into them.
                    min: GestureSettingStateNotifier.minSwipeDownThreshold,
                    max: GestureSettingStateNotifier.maxSwipeDownThreshold,
                    divisions: 15,
                    labelFor: (value) => context.t.unitPx(value: value.round()),
                    helperFor: (value) => context.t.settingsPage
                        .swipeDownThresholdDesc(threshold: value.round()),
                    // Once per drag, not once per step: the threshold is only
                    // interesting after the finger leaves the thumb.
                    onChangeEnd: gestureNotifier.updateSwipeDownThreshold,
                  ),
                ],
              ),
              // An action is a row, like every other immediate action in
              // settings; a button floating inside a block was the only one of
              // its kind.
              SettingsSection(
                title: context.t.settingsPage.reset,
                children: [
                  ListTile(
                    title: Text(context.t.resetToDefault),
                    leading: const Icon(Icons.restore),
                    onTap: () async {
                      final t = context.t;
                      final kept = await gestureNotifier.reset();
                      if (!context.mounted) return;
                      // The row used to promise the defaults before the writes
                      // had even answered, and on a run whose settings box
                      // never opened they were gone again with the process.
                      showToast(
                        context,
                        kept
                            ? t.settingsPage.resetSuccess
                            : t.settingsPage.resetNotSaved,
                      );
                    },
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
