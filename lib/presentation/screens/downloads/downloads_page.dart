import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/data/repository/downloads/entity/download_progress.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/screens/downloads/download_entry_view.dart';
import 'package:boorusphere/presentation/screens/downloads/download_filter.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/confirm_destructive.dart';
import 'package:boorusphere/presentation/widgets/empty_state.dart';
import 'package:boorusphere/presentation/widgets/expandable_group_list_view.dart';
import 'package:boorusphere/presentation/widgets/settings_sheet.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Statuses of every tracked download as one comparable value. A percent tick
/// leaves it unchanged, so a page watching it is not rebuilt per tick. Entries
/// are sorted because a status update moves its row to the end of the list.
String _statusSignature(List<DownloadProgress> progresses) {
  final statuses = progresses.map((it) => '${it.id}:${it.status.name}').toList()
    ..sort();
  return statuses.join(';');
}

@RoutePage()
class DownloadsPage extends HookConsumerWidget {
  const DownloadsPage({super.key, this.session});
  final SearchSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedServerId = ref.read(
      serverSettingStateProvider.select((it) => it.lastActiveId),
    );
    final session = this.session ?? SearchSession(serverId: savedServerId);
    final servers = ref.watch(serverStateProvider);
    final downloadEntries = ref
        .watch(downloadEntryStateProvider)
        .whereNotReserved()
        .toList();
    // Percent ticks arrive several times a second per running download, and
    // only a status change can move an entry in or out of the active filter.
    // Keying the rebuild on the statuses keeps the list still while a file
    // downloads; the values are then read fresh for the filter itself.
    ref.watch(downloadProgressStateProvider.select(_statusSignature));
    final downloadProgressState = ref.read(downloadProgressStateProvider);
    final groupByServer = ref.watch(
      downloadSettingStateProvider.select((it) => it.groupByServer),
    );
    final filter = useState(DownloadFilter.none);
    List<DownloadEntry> filteredEntries = downloadEntries;
    if (filter.value != DownloadFilter.none) {
      filteredEntries = downloadEntries
          .where(
            (it) =>
                downloadProgressState.getById(it.id).status ==
                filter.value.toStatus(),
          )
          .toList();
    }

    return ProviderScope(
      overrides: [searchSessionProvider.overrideWith((ref) => session)],
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t.downloads.title),
          actions: [
            if (downloadEntries.isNotEmpty)
              PopupMenuButton(
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onSelected: (value) {
                  switch (value) {
                    case 'filter':
                      showFilterDialog(context, filter.value).then((value) {
                        if (value != null) {
                          filter.value = value;
                        }
                      });
                      break;
                    case 'clear-all':
                      showClearDialog(context).then((value) {
                        if (value) {
                          ref.read(downloadEntryStateProvider.notifier).clear();
                        }
                      });
                      break;
                    case 'group-by-server':
                      ref
                          .read(downloadSettingStateProvider.notifier)
                          .setGroupByServer(!groupByServer);
                      break;
                    default:
                      break;
                  }
                },
                itemBuilder: (context) {
                  return [
                    PopupMenuItem(
                      value: 'filter',
                      child: Text(context.t.downloads.filterByStatus),
                    ),
                    PopupMenuItem(
                      value: 'group-by-server',
                      child: Text(
                        groupByServer
                            ? context.t.downloads.ungroup
                            : context.t.downloads.groupByServer,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear-all',
                      child: Text(context.t.downloads.clearAll),
                    ),
                  ];
                },
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // A filtered list has to say so: the chip names the filter and
              // is the control that turns it off again.
              if (filter.value != DownloadFilter.none)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingSm,
                    DesignTokens.spacingMd,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(
                        Icons.filter_list,
                        size: DesignTokens.iconInline,
                      ),
                      label: Text(filter.value.describe(context)),
                      onDeleted: () => filter.value = DownloadFilter.none,
                      deleteIcon: const Icon(
                        Icons.close_rounded,
                        size: DesignTokens.iconInline,
                      ),
                      deleteButtonTooltipMessage: context.t.clear,
                    ),
                  ),
                ),
              Expanded(
                child: filteredEntries.isEmpty
                    ? EmptyState(
                        icon: Icon(
                          downloadEntries.isEmpty
                              ? Icons.cloud_download
                              : Icons.filter_list_off,
                        ),
                        title: downloadEntries.isEmpty
                            ? context.t.downloads.placeholder
                            : context.t.downloads.noMatch,
                        body: downloadEntries.isEmpty
                            ? context.t.downloadsHint
                            : null,
                      )
                    : ExpandableGroupListView<DownloadEntry, String>(
                        items: filteredEntries,
                        groupedBy: (item) => item.post.serverId,
                        groupTitle: (id) => Text(
                          servers.getById(id, or: servers.firstOrNull).name,
                          style: context.theme.textTheme.bodyLarge,
                        ),
                        itemBuilder: (item) => DownloadEntryView(
                          entry: item,
                          groupByServer: groupByServer,
                        ),
                        ungroup: !groupByServer,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<DownloadFilter?> showFilterDialog(
    BuildContext context,
    DownloadFilter current,
  ) async {
    final picked = await showChoiceSheet<DownloadFilter>(
      context: context,
      title: context.t.downloads.filterByStatus,
      selected: current,
      choices: [
        for (final filter in DownloadFilter.values)
          Choice(value: filter, label: filter.describe(context)),
      ],
    );
    return picked?.value;
  }

  Future<bool> showClearDialog(BuildContext context) {
    return confirmDestructive(
      context,
      icon: Icons.delete_forever,
      title: context.t.downloads.clearAll,
      message: context.t.downloads.clearAllWarning,
      confirmLabel: context.t.clear,
    );
  }
}
