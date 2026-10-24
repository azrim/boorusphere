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
import 'package:boorusphere/presentation/widgets/drag_handle.dart';
import 'package:boorusphere/presentation/widgets/permissions.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloaderDialog extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(postHeadersFactoryProvider(post));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const DragHandle(),
            ListTile(title: Text(context.t.downloads.title)),
            if (post.sampleFile.isNotEmpty)
              ListTile(
                title: Text(context.t.fileSample),
                subtitle: FutureBuilder<PixelSize>(
                  future:
                      (post.content.isPhoto || post.content.isGif) &&
                          !post.sampleSize.hasPixels
                      ? CachedNetworkImageProvider(
                          post.sampleFile,
                          headers: headers,
                        ).resolvePixelSize()
                      : Future.value(post.sampleSize),
                  builder: (context, snapshot) {
                    final size = snapshot.data ?? post.sampleSize;
                    return Text('$size, ${post.sampleFile.fileExt}');
                  },
                ),
                leading: Icon(_getFileIcon(post.sampleFile)),
                onTap: () async {
                  // Resolved before the permission prompt: the reader can be
                  // disposed while it is open, and a read after that throws.
                  final downloader = ref.read(downloaderProvider);
                  // The permission only gates the completion notice, so a
                  // denial must not block the download.
                  await checkNotificationPermission(context);
                  onItemClick?.call('sample');
                  unawaited(downloader.download(post, url: post.sampleFile));
                  if (context.mounted) {
                    context.navigator.pop();
                  }
                },
              ),
            ListTile(
              title: Text(context.t.fileOg),
              subtitle: Text(
                '${post.originalSize.toString()}, ${post.originalFile.fileExt}',
              ),
              leading: Icon(_getFileIcon(post.originalFile)),
              onTap: () async {
                // Resolved before the permission prompt: the reader can be
                // disposed while it is open, and a read after that throws.
                final downloader = ref.read(downloaderProvider);
                // The permission only gates the completion notice, so a
                // denial must not block the download.
                await checkNotificationPermission(context);
                onItemClick?.call('original');
                unawaited(downloader.download(post));
                if (context.mounted) {
                  context.navigator.pop();
                }
              },
            ),
          ],
        ),
      ),
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
      await showModalBottomSheet(
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
