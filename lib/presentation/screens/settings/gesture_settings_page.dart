import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
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
    final gestureNotifier =
        ref.read(gestureSettingStateNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gesture Settings'),
      ),
      body: StyledOverlayRegion(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Swipe Mode Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swipe Mode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose how to navigate between posts',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      _SwipeModeSelector(
                        currentMode: gestureSettings.swipeMode,
                        onModeChanged: gestureNotifier.updateSwipeMode,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Swipe Actions Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swipe Actions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Swipe to Details'),
                        subtitle: const Text(
                            'Swipe up to open post details (horizontal mode)'),
                        value: gestureSettings.enableSwipeToDetails,
                        onChanged: (_) =>
                            gestureNotifier.toggleSwipeToDetails(),
                      ),
                      SwitchListTile(
                        title: const Text('Swipe to Dismiss'),
                        subtitle: const Text(
                            'Swipe down to close viewer (horizontal mode)'),
                        value: gestureSettings.enableSwipeToDismiss,
                        onChanged: (_) =>
                            gestureNotifier.toggleSwipeToDismiss(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Sensitivity Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sensitivity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        title: const Text('Swipe Down Threshold'),
                        subtitle: Text(
                          'Distance required to trigger dismiss: ${gestureSettings.swipeDownThreshold.round()}px',
                        ),
                        trailing: SizedBox(
                          width: 200,
                          child: Slider(
                            value: gestureSettings.swipeDownThreshold,
                            min: 50,
                            max: 200,
                            divisions: 15,
                            onChanged: gestureNotifier.updateSwipeDownThreshold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Reset Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reset',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          gestureNotifier.reset();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Gesture settings reset to defaults'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('Reset to Defaults'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeModeSelector extends StatelessWidget {
  const _SwipeModeSelector({
    required this.currentMode,
    required this.onModeChanged,
  });

  final SwipeMode currentMode;
  final ValueChanged<SwipeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SwipeModeOption(
          mode: SwipeMode.horizontal,
          title: 'Horizontal',
          subtitle: 'Swipe left/right to navigate between posts',
          icon: Icons.swap_horiz,
          isSelected: currentMode == SwipeMode.horizontal,
          onTap: () => onModeChanged(SwipeMode.horizontal),
        ),
        const SizedBox(height: 8),
        _SwipeModeOption(
          mode: SwipeMode.vertical,
          title: 'Vertical',
          subtitle: 'Swipe up/down to navigate between posts',
          icon: Icons.swap_vert,
          isSelected: currentMode == SwipeMode.vertical,
          onTap: () => onModeChanged(SwipeMode.vertical),
        ),
      ],
    );
  }
}

class _SwipeModeOption extends StatelessWidget {
  const _SwipeModeOption({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final SwipeMode mode;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.onPrimaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
