import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_lock/app_lock_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/content_setting.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:boorusphere/presentation/provider/settings/gesture_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/settings/widgets/settings_section.dart';
import 'package:boorusphere/presentation/theme/color_palettes.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/gestures/swipe_mode.dart';
import 'package:boorusphere/presentation/utils/hooks/markmayneedrebuild.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.settings.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
          ),
          children: [
            SettingsSection(
              title: context.t.downloads.title,
              children: const [_HideMedia(), _DownloadQuality()],
            ),
            SettingsSection(
              title: context.t.settings.interface,
              children: const [
                _Language(),
                _FeedMode(),
                _GestureSettings(),
                _MidnightMode(),
                _ColorPalette(),
                _UiBlur(),
              ],
            ),
            SettingsSection(
              title: context.t.settings.viewer.title,
              children: const [
                _SlideshowDirection(),
                _SlideshowInterval(),
                _VideoSeekStep(),
                _VolumeKeyNavigation(),
              ],
            ),
            SettingsSection(
              title: context.t.settings.safeMode,
              children: const [
                _BlurContent(),
                _BlurTimelineOnly(),
                _HideFavorited(),
                _HideDownloaded(),
                _ImeIncognito(),
              ],
            ),
            SettingsSection(
              title: context.t.settings.privacy,
              children: const [_Privacy()],
            ),
            SettingsSection(
              title: context.t.servers.title,
              children: const [_LoadOriginal(), _PostLimit()],
            ),
            SettingsSection(
              title: context.t.settings.misc,
              children: const [_BackupRestore(), _ClearCache(), _VideoCache()],
            ),
          ],
        ),
      ),
    );
  }
}

class _HideMedia extends HookConsumerWidget {
  const _HideMedia();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharedStorageHandle = ref.watch(sharedStorageHandleProvider);
    final markRebuild = useMarkMayNeedRebuild();

    return SwitchListTile(
      title: Text(context.t.settings.hideMedia.title),
      subtitle: RowSubtitle(Text(context.t.settings.hideMedia.desc)),
      value: sharedStorageHandle.isHidden,
      onChanged: (value) async {
        await sharedStorageHandle.hide(value);
        markRebuild();
      },
    );
  }
}

class _DownloadQuality extends ConsumerWidget {
  const _DownloadQuality();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(
      downloadSettingStateProvider.select((it) => it.quality),
    );
    return ListTile(
      title: Text(context.t.downloads.quality),
      subtitle: RowSubtitle(Text(quality.describe(context))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showChoiceSheet<DownloadQuality>(
          context: context,
          title: context.t.downloads.quality,
          selected: quality,
          choices: DownloadQuality.values
              .map((it) => Choice(value: it, label: it.describe(context)))
              .toList(),
        );
        if (picked == null) return;
        await ref
            .read(downloadSettingStateProvider.notifier)
            .setQuality(picked.value);
      },
    );
  }
}

class _CurrentLanguage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiSettingStateProvider.select((ui) => ui.locale));

    return Text(locale == null ? context.t.auto : context.t.languageName);
  }
}

class _MidnightMode extends ConsumerWidget {
  const _MidnightMode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.midnightTheme.title),
      subtitle: RowSubtitle(Text(context.t.settings.midnightTheme.desc)),
      value: ref.watch(uiSettingStateProvider.select((ui) => ui.midnightMode)),
      onChanged: (value) {
        ref.read(uiSettingStateProvider.notifier).setMidnightMode(value);
      },
    );
  }
}

class _ColorPalette extends ConsumerWidget {
  const _ColorPalette();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPalette = ref.watch(uiSettingStateProvider).colorPalette;

    return ListTile(
      title: Text(context.t.settingsPage.colorPalette),
      subtitle: RowSubtitle(Text(currentPalette.displayName)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showChoiceSheet<ColorPalette>(
          context: context,
          title: context.t.settingsPage.colorPalette,
          selected: currentPalette,
          choices: ColorPalette.values
              .map(
                (it) => Choice(
                  value: it,
                  label: it.displayName,
                  leading: _PaletteSwatch(palette: it),
                ),
              )
              .toList(),
        );
        if (picked == null) return;
        await ref
            .read(uiSettingStateProvider.notifier)
            .setColorPalette(picked.value);
      },
    );
  }
}

/// Previews a palette with its own page and accent colours, so the list reads
/// as themes rather than as a row of dots.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.palette});

  final ColorPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = paletteColorsFor(palette, Theme.of(context).brightness);
    final accent = palette.accentColor;

    if (colors == null) {
      return accent == null
          ? const Icon(Icons.brightness_auto)
          : Container(
              width: DesignTokens.iconChipSize,
              height: DesignTokens.iconChipSize,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            );
    }

    return Container(
      width: DesignTokens.iconChipSize,
      height: DesignTokens.iconChipSize,
      decoration: BoxDecoration(
        color: colors.background,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      alignment: Alignment.center,
      child: Container(
        width: DesignTokens.iconChipSize / 2,
        height: DesignTokens.iconChipSize / 2,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _UiBlur extends ConsumerWidget {
  const _UiBlur();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.uiBlur.title),
      subtitle: RowSubtitle(Text(context.t.settings.uiBlur.desc)),
      value: ref.watch(uiSettingStateProvider.select((ui) => ui.blur)),
      onChanged: (value) {
        ref.read(uiSettingStateProvider.notifier).showBlur(value);
      },
    );
  }
}

String _slideshowDirectionLabel(
  BuildContext context,
  SlideshowDirection direction,
) {
  return switch (direction) {
    SlideshowDirection.forward => context.t.settings.viewer.slideshowForward,
    SlideshowDirection.backward => context.t.settings.viewer.slideshowBackward,
    SlideshowDirection.random => context.t.settings.viewer.slideshowRandom,
  };
}

class _SlideshowDirection extends ConsumerWidget {
  const _SlideshowDirection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direction = ref.watch(
      contentSettingStateProvider.select((it) => it.slideshowDirection),
    );

    return ListTile(
      title: Text(context.t.settings.viewer.slideshowDirection),
      subtitle: RowSubtitle(Text(_slideshowDirectionLabel(context, direction))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showChoiceSheet<SlideshowDirection>(
          context: context,
          title: context.t.settings.viewer.slideshowDirection,
          selected: direction,
          choices: [
            for (final value in SlideshowDirection.values)
              Choice(
                value: value,
                label: _slideshowDirectionLabel(context, value),
                leading: Icon(switch (value) {
                  SlideshowDirection.forward => Icons.arrow_forward,
                  SlideshowDirection.backward => Icons.arrow_back,
                  SlideshowDirection.random => Icons.shuffle,
                }),
              ),
          ],
        );
        if (picked == null) return;
        await ref
            .read(contentSettingStateProvider.notifier)
            .setSlideshowDirection(picked.value);
      },
    );
  }
}

class _SlideshowInterval extends ConsumerWidget {
  const _SlideshowInterval();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(
      contentSettingStateProvider.select((it) => it.slideshowInterval),
    );

    return SettingsSliderTile(
      title: context.t.settings.viewer.slideshowInterval,
      value: interval.toDouble(),
      min: ContentSettingState.minSlideshowInterval.toDouble(),
      max: ContentSettingState.maxSlideshowInterval.toDouble(),
      divisions:
          ContentSettingState.maxSlideshowInterval -
          ContentSettingState.minSlideshowInterval,
      valueLabel: '$interval',
      helper: context.t.settings.viewer.slideshowIntervalDesc(
        seconds: interval,
      ),
      onChanged: (value) {
        ref
            .read(contentSettingStateProvider.notifier)
            .setSlideshowInterval(value.round());
      },
    );
  }
}

class _VideoSeekStep extends ConsumerWidget {
  const _VideoSeekStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(
      contentSettingStateProvider.select((it) => it.videoSeekSeconds),
    );

    return SettingsSliderTile(
      title: context.t.settings.viewer.doubleTapSeek,
      value: seconds.toDouble(),
      min: ContentSettingState.minVideoSeekSeconds.toDouble(),
      max: ContentSettingState.maxVideoSeekSeconds.toDouble(),
      divisions:
          ContentSettingState.maxVideoSeekSeconds -
          ContentSettingState.minVideoSeekSeconds,
      valueLabel: '$seconds',
      helper: context.t.settings.viewer.doubleTapSeekDesc(seconds: seconds),
      onChanged: (value) {
        ref
            .read(contentSettingStateProvider.notifier)
            .setVideoSeekSeconds(value.round());
      },
    );
  }
}

class _VolumeKeyNavigation extends ConsumerWidget {
  const _VolumeKeyNavigation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.viewer.volumeKeys),
      subtitle: RowSubtitle(Text(context.t.settings.viewer.volumeKeysDesc)),
      value: ref.watch(
        contentSettingStateProvider.select((it) => it.volumeKeyNavigation),
      ),
      onChanged: (value) {
        ref
            .read(contentSettingStateProvider.notifier)
            .setVolumeKeyNavigation(value);
      },
    );
  }
}

class _BlurContent extends ConsumerWidget {
  const _BlurContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.blurContent.title),
      subtitle: RowSubtitle(Text(context.t.settings.blurContent.desc)),
      value: ref.watch(
        contentSettingStateProvider.select((it) => it.blurExplicit),
      ),
      onChanged: (value) {
        ref
            .read(contentSettingStateProvider.notifier)
            .setBlurExplicitPost(value);
      },
    );
  }
}

class _BlurTimelineOnly extends ConsumerWidget {
  const _BlurTimelineOnly();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentSettings = ref.watch(contentSettingStateProvider);

    setBlurTimelineOnly(value) {
      ref.read(contentSettingStateProvider.notifier).setBlurTimelineOnly(value);
    }

    return SwitchListTile(
      title: Text(context.t.settings.blurTimelineOnly.title),
      subtitle: RowSubtitle(Text(context.t.settings.blurTimelineOnly.desc)),
      value: contentSettings.blurTimelineOnly,
      onChanged: contentSettings.blurExplicit ? setBlurTimelineOnly : null,
    );
  }
}

class _HideFavorited extends ConsumerWidget {
  const _HideFavorited();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.hideFavorited.title),
      subtitle: RowSubtitle(Text(context.t.settings.hideFavorited.desc)),
      value: ref.watch(
        contentSettingStateProvider.select((it) => it.hideFavorited),
      ),
      onChanged: (value) {
        ref.read(contentSettingStateProvider.notifier).setHideFavorited(value);
      },
    );
  }
}

class _HideDownloaded extends ConsumerWidget {
  const _HideDownloaded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.hideDownloaded.title),
      subtitle: RowSubtitle(Text(context.t.settings.hideDownloaded.desc)),
      value: ref.watch(
        contentSettingStateProvider.select((it) => it.hideDownloaded),
      ),
      onChanged: (value) {
        ref.read(contentSettingStateProvider.notifier).setHideDownloaded(value);
      },
    );
  }
}

class _Privacy extends ConsumerWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);

    return ListTile(
      title: Text(context.t.appLock.title),
      subtitle: RowSubtitle(
        Text(
          lock.isActive
              ? context.t.appLock.summaryOn
              : context.t.appLock.summaryOff,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        context.router.push(const AppLockRoute());
      },
    );
  }
}

class _ImeIncognito extends ConsumerWidget {
  const _ImeIncognito();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.imeIncognito.title),
      subtitle: RowSubtitle(Text(context.t.settings.imeIncognito.desc)),
      value: ref.watch(uiSettingStateProvider.select((ui) => ui.imeIncognito)),
      onChanged: (value) {
        ref.read(uiSettingStateProvider.notifier).setImeIncognito(value);
      },
    );
  }
}

class _Language extends ConsumerWidget {
  const _Language();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiSettingStateProvider.select((ui) => ui.locale));

    return ListTile(
      title: Text(context.t.settings.lang.title),
      subtitle: RowSubtitle(_CurrentLanguage()),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showChoiceSheet<AppLocale?>(
          context: context,
          title: context.t.settings.lang.title,
          selected: locale,
          choices: [
            Choice(
              value: null,
              label: context.t.auto,
              detail: context.t.settings.lang.auto,
            ),
            ...AppLocale.values.map((it) {
              final name = it.translations.languageName;
              final alias = it.translations.languageAlias;
              return Choice(
                value: it,
                label: name,
                // The alias repeats the name for several locales; only show
                // it when it adds a second spelling.
                detail: alias == name ? null : alias,
              );
            }),
          ],
        );
        if (picked == null) return;
        await ref.read(uiSettingStateProvider.notifier).setLocale(picked.value);
      },
    );
  }
}

class _FeedMode extends ConsumerWidget {
  const _FeedMode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(uiSettingStateProvider.select((it) => it.feedMode));

    return ListTile(
      title: Text(context.t.settings.feedMode.title),
      subtitle: RowSubtitle(
        Text(
          mode == FeedMode.infinite
              ? context.t.settings.feedMode.infinite
              : context.t.settings.feedMode.paged,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showChoiceSheet<FeedMode>(
          context: context,
          title: context.t.settings.feedMode.title,
          selected: mode,
          choices: [
            Choice(
              value: FeedMode.paged,
              label: context.t.settings.feedMode.paged,
              detail: context.t.settings.feedMode.pagedDesc,
              leading: const Icon(Icons.swap_horiz_rounded),
            ),
            Choice(
              value: FeedMode.infinite,
              label: context.t.settings.feedMode.infinite,
              detail: context.t.settings.feedMode.infiniteDesc,
              leading: const Icon(Icons.expand_more_rounded),
            ),
          ],
        );
        if (picked == null) return;
        await ref
            .read(uiSettingStateProvider.notifier)
            .setFeedMode(picked.value);
      },
    );
  }
}

class _GestureSettings extends ConsumerWidget {
  const _GestureSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swipeMode = ref.watch(
      gestureSettingStateProvider.select((it) => it.swipeMode),
    );

    return ListTile(
      title: Text(context.t.settingsPage.gestureSettings),
      subtitle: RowSubtitle(
        Text(
          swipeMode == SwipeMode.horizontal
              ? context.t.settingsPage.swipeHorizontal
              : context.t.settingsPage.swipeVertical,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        context.router.push(const GestureSettingsRoute());
      },
    );
  }
}

class _LoadOriginal extends ConsumerWidget {
  const _LoadOriginal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(context.t.settings.loadOg.title),
      subtitle: RowSubtitle(Text(context.t.settings.loadOg.desc)),
      value: ref.watch(
        contentSettingStateProvider.select((it) => it.loadOriginal),
      ),
      onChanged: (value) {
        ref
            .read(contentSettingStateProvider.notifier)
            .setLoadOriginalPost(value);
      },
    );
  }
}

class _PostLimit extends ConsumerWidget {
  const _PostLimit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(context.t.settings.postLimit.title),
      subtitle: RowSubtitle(Text(context.t.settings.postLimit.desc)),
      trailing: DropdownButton(
        menuMaxHeight: 178,
        value: ref.watch(
          serverSettingStateProvider.select((it) => it.postLimit),
        ),
        elevation: DesignTokens.elevationOverlay.toInt(),
        underline: const SizedBox.shrink(),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusXl),
        ),
        items: List<DropdownMenuItem<int>>.generate(10, (i) {
          final x = i * 10 + 10;
          return DropdownMenuItem(value: x, child: Text('$x'));
        }),
        onChanged: (value) {
          ref
              .read(serverSettingStateProvider.notifier)
              .setPostLimit(value as int);
        },
      ),
    );
  }
}

class _BackupRestore extends StatelessWidget {
  const _BackupRestore();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(context.t.dataBackup.title),
      subtitle: RowSubtitle(Text(context.t.dataBackup.desc)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        context.router.push(const DataBackupRoute());
      },
    );
  }
}

class _ClearCache extends ConsumerWidget {
  const _ClearCache();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(context.t.settings.clearCache.title),
      subtitle: RowSubtitle(Text(context.t.settings.clearCache.desc)),
      onTap: () async {
        showToast(context, context.t.clearing);

        await DefaultCacheManager().emptyCache();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        if (context.mounted) {
          showToast(context, context.t.settings.clearCache.done);
        }
      },
    );
  }
}

/// Shows how much the viewer's videos take up and empties it on request.
///
/// The size is read when the page opens: it is a directory walk, not something
/// to run on every rebuild.
class _VideoCache extends ConsumerStatefulWidget {
  const _VideoCache();

  @override
  ConsumerState<_VideoCache> createState() => _VideoCacheState();
}

class _VideoCacheState extends ConsumerState<_VideoCache> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSize());
  }

  Future<void> _refreshSize() async {
    final bytes = await ref.read(videoCacheProvider).sizeBytes();
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    final confirmed = await confirmDestructive(
      context,
      title: context.t.settings.videoCache.clearTitle,
      message: context.t.settings.videoCache.clearMessage,
      confirmLabel: context.t.clear,
    );
    if (!confirmed || !mounted) return;

    showToast(context, context.t.clearing);
    await ref.read(videoCacheProvider).clear();
    await _refreshSize();
    if (mounted) showToast(context, context.t.settings.videoCache.done);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes ?? 0;
    return ListTile(
      title: Text(context.t.settings.videoCache.title),
      subtitle: RowSubtitle(Text(context.t.settings.videoCache.desc)),
      trailing: bytes <= 0 ? null : Text(_formatBytes(bytes)),
      onTap: _clear,
    );
  }
}

String _formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}
