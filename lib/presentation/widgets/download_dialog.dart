import 'dart:async';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/images.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/permissions.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloaderDialog extends HookConsumerWidget {
  const DownloaderDialog({super.key, required this.post, this.onItemClick});

  final Post post;
  final Function(String type)? onItemClick;

  IconData _getFileIcon(String url) {
    if (url.mimeType.startsWith('video')) {
      return Icons.video_library;
    } else if (url.mimeType.startsWith('image')) {
      if (url.fileExt.toLowerCase() == 'gif') {
        return Icons.gif_box;
      }
      return Icons.photo;
    } else {
      return Icons.file_present;
    }
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    String type,
    String url,
  ) async {
    // Resolved before the permission prompt: the reader can be disposed while
    // it is open, and a read after that throws.
    final downloader = ref.read(downloaderProvider);
    // The permission only gates the completion notice, so a denial must not
    // block the download.
    await checkNotificationPermission(context);
    onItemClick?.call(type);
    unawaited(downloader.download(post, url: url));
    if (context.mounted) {
      context.navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));
    // A sample without its pixel size is probed once and kept: rebuilding the
    // future per build would restart the read and blank the row.
    final sampleSize = useMemoized<Future<PixelSize>>(() {
      if ((post.content.isPhoto || post.content.isGif) &&
          !post.sampleSize.hasPixels) {
        return CachedNetworkImageProvider(
          post.sampleFile,
          headers: headers,
        ).resolvePixelSize();
      }
      return Future.value(post.sampleSize);
    }, [headers, post]);

    return FutureBuilder<PixelSize>(
      future: sampleSize,
      builder: (context, snapshot) {
        final size = snapshot.data ?? post.sampleSize;
        return SheetShell(
          title: context.t.downloads.title,
          child: SingleChildScrollView(
            child: SheetPanel(
              children: [
                if (post.sampleFile.isNotEmpty)
                  SheetRow(
                    title: context.t.fileSample,
                    detail: '$size, ${post.sampleFile.fileExt}',
                    leading: Icon(_getFileIcon(post.sampleFile)),
                    onTap: () =>
                        _download(context, ref, 'sample', post.sampleFile),
                  ),
                SheetRow(
                  title: context.t.fileOg,
                  detail:
                      '${post.originalSize.toString()}, '
                      '${post.originalFile.fileExt}',
                  leading: Icon(_getFileIcon(post.originalFile)),
                  onTap: () =>
                      _download(context, ref, 'original', post.originalFile),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Whether a download started: `null` when the reader closed the picker
  /// without choosing, `false` when the download could not be started at all.
  static Future<bool?> show(
    BuildContext context,
    WidgetRef ref,
    Post post, {
    Function(String type)? onItemClick,
  }) async {
    // Resolved before the first await: the caller's element can be disposed
    // while a sheet or a permission prompt is open, and a read after that
    // throws instead of starting the download.
    final downloader = ref.read(downloaderProvider);
    final quality = ref.read(
      downloadSettingStateProvider.select((it) => it.quality),
    );

    if (quality == DownloadQuality.ask) {
      var chosen = false;
      await showSheet<void>(
        context: context,
        builder: (_) => DownloaderDialog(
          post: post,
          onItemClick: (type) {
            chosen = true;
            onItemClick?.call(type);
          },
        ),
      );

      return chosen ? true : null;
    }

    // The permission only gates the completion notice, so a denial must not
    // block the download.
    await checkNotificationPermission(context);

    final isSample = quality == DownloadQuality.sample;
    final taskId = await downloader.download(
      post,
      // Engines without a sample report an empty URL, so the original is the
      // only downloadable file there.
      url: isSample && post.sampleFile.isNotEmpty
          ? post.sampleFile
          : post.originalFile,
    );
    if (taskId == null) return false;

    // The previous record is only dropped once the replacement is running, so
    // a failed start leaves it in place.
    onItemClick?.call(isSample ? 'sample' : 'original');
    return true;
  }
}

Future<bool> checkNotificationPermission(BuildContext context) async {
  final isGranted = await Permission.notification.isGranted;
  if (isGranted) {
    return true;
  }

  final status = await Permission.notification.request();
  if (!status.isGranted && context.mounted) {
    await showSystemAppSettingsDialog(
      context: context,
      title: context.t.downloads.title,
      reason: context.t.downloads.noPermission,
    );
  }
  return status.isGranted;
}
