import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_status.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/presentation/widgets/row_subtitle.dart';
import 'package:boorusphere/utils/extensions/number.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:cached_network_image/cached_network_image.dart'
    hide DownloadProgress;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:separated_row/separated_row.dart';

class DownloadEntryView extends HookConsumerWidget {
  const DownloadEntryView({
    super.key,
    required this.entry,
    required this.groupByServer,
  });

  final DownloadEntry entry;
  final bool groupByServer;

  IconData _buildStatusIcon(DownloadProgress progress, bool isFileExists) {
    switch (progress.status) {
      case DownloadStatus.downloaded:
        return isFileExists
            ? Icons.download_done_rounded
            : Icons.error_outline_rounded;
      case DownloadStatus.downloading:
        return Icons.downloading_rounded;
      case DownloadStatus.canceled:
      case DownloadStatus.failed:
        return Icons.cancel_rounded;
      default:
        return Icons.file_open;
    }
  }

  Color _buildStatusColor(
    ColorScheme scheme,
    DownloadProgress progress,
    bool isFileExists,
  ) {
    switch (progress.status) {
      case DownloadStatus.downloaded:
        return isFileExists ? scheme.primary : scheme.onSurfaceVariant;
      case DownloadStatus.canceled:
      case DownloadStatus.failed:
        return scheme.error;
      default:
        return scheme.onSurface;
    }
  }

  String _buildStatusDesc(
    BuildContext context,
    DownloadProgress progress,
    bool isFileExists,
  ) {
    if (progress.status.isDownloaded && !isFileExists) {
      return context.t.downloads.noFile;
    }

    final status = context.t.downloads.status;
    switch (progress.status) {
      case DownloadStatus.pending:
        return status.pending;
      case DownloadStatus.downloading:
        return status.downloading;
      case DownloadStatus.downloaded:
        return status.downloaded;
      case DownloadStatus.failed:
        return status.failed;
      case DownloadStatus.canceled:
        return status.canceled;
      case DownloadStatus.paused:
        return status.paused;
      default:
        return status.empty;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final headers = ref.watch(postHeadersFactoryProvider(entry.post));
    // Scoped to this entry: watching the whole list rebuilt every row for each
    // percent tick of any running download.
    final progress = ref.watch(
      downloadProgressStateProvider.select((it) => it.getById(entry.id)),
    );
    // A stat per rebuild would run for every percent tick of a running
    // download, so the answer is kept until the folder or the status changes.
    final revision = ref.watch(downloadFileRevisionProvider);
    final isFileExists = useMemoized(
      () => ref.read(sharedStorageHandleProvider).fileExists(entry.dest),
      [revision, entry.dest, progress.status],
    );

    return ListTile(
      title: Text(
        Uri.decodeFull(entry.dest.fileName),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: RowSubtitle(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: [
                SeparatedRow(
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: DesignTokens.spacingXs),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _buildStatusIcon(progress, isFileExists),
                      color: _buildStatusColor(
                        context.colorScheme,
                        progress,
                        isFileExists,
                      ),
                      size: DesignTokens.iconInline,
                    ),
                    Text(_buildStatusDesc(context, progress, isFileExists)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: DesignTokens.iconInline,
                      child: Center(child: Text('•')),
                    ),
                    Text(
                      servers
                          .getById(entry.post.serverId, or: servers.firstOrNull)
                          .name,
                    ),
                  ],
                ),
              ],
            ),
            // A download is a length, not a turn: the bar fills the row under
            // the status line and the percentage reads beside it.
            if (progress.status.isDownloading || progress.status.isPending) ...[
              const SizedBox(height: DesignTokens.spacingXs),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                      child: LinearProgressIndicator(
                        value: progress.status.isPending
                            ? null
                            : progress.progress.ratio,
                        minHeight: 3,
                        backgroundColor:
                            context.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Text(
                    '${progress.progress}%',
                    style: AppTextRoles.of(context).numeric,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      leading: DownloadImagePreview(entry: entry, headers: headers),
      trailing: _EntryPopupMenu(
        entry: entry,
        progress: progress,
        server: servers.getById(entry.post.serverId, or: servers.firstOrNull),
        isFileExists: isFileExists,
      ),
      onTap: !progress.status.isDownloaded || !isFileExists
          ? null
          : () => ref.read(downloaderProvider).openFile(id: entry.id),
    );
  }
}

class DownloadImagePreview extends HookWidget {
  const DownloadImagePreview({
    super.key,
    required this.entry,
    required this.headers,
  });

  /// Display width of the thumbnail, in dp.
  static const double size = 42;

  final DownloadEntry entry;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    // Decode at the size the thumbnail is drawn at: a booru preview is
    // several megapixels, and a row that keeps the full decode in memory
    // costs megabytes for a 42 dp square.
    final cacheWidth = (size * context.mqDpr).round();

    return ClipRRect(
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.radiusSm),
      ),
      child: CachedNetworkImage(
        imageUrl: entry.post.previewFile,
        httpHeaders: headers,
        width: size,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _EntryPopupMenu extends ConsumerWidget {
  const _EntryPopupMenu({
    required this.entry,
    required this.progress,
    required this.server,
    required this.isFileExists,
  });

  final DownloadEntry entry;
  final DownloadProgress progress;
  final Server server;
  final bool isFileExists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      onSelected: (value) async {
        final downloader = ref.read(downloaderProvider);
        switch (value) {
          case 'redownload':
            await DownloaderDialog.show(
              context,
              ref,
              entry.post,
              onItemClick: (type) async {
                await downloader.clear(id: entry.id);
              },
            );
            break;
          case 'retry':
            await downloader.retry(id: entry.id);
            break;
          case 'cancel':
            await downloader.cancel(id: entry.id);
            break;
          case 'delete-file':
            final confirmed = await confirmDestructive(
              context,
              title: context.t.downloads.deleteFile,
              message: context.t.downloads.deleteFileWarning,
              confirmLabel: context.t.downloads.deleteFile,
            );
            if (!confirmed) return;
            await downloader.deleteContent(entry);
            break;
          case 'clear':
            await downloader.clear(id: entry.id);
            break;
          default:
            break;
        }
      },
      itemBuilder: (context) {
        return [
          if (progress.status.isDownloaded && !isFileExists)
            PopupMenuItem(
              value: 'redownload',
              child: Text(context.t.downloads.redownload),
            ),
          if (progress.status.isCanceled || progress.status.isFailed)
            PopupMenuItem(value: 'retry', child: Text(context.t.retry)),
          if (progress.status.isDownloading)
            PopupMenuItem(value: 'cancel', child: Text(context.t.cancel)),
          if (isFileExists)
            PopupMenuItem(
              value: 'delete-file',
              child: Text(context.t.downloads.deleteFile),
            ),
          PopupMenuItem(value: 'clear', child: Text(context.t.clear)),
        ];
      },
    );
  }
}
