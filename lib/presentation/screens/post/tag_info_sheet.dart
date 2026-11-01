import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_category.dart';
import 'package:boorusphere/data/repository/booru/entity/tag_info.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/tag_info_cache.dart';
import 'package:boorusphere/presentation/provider/booru/tag_info_state.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/sheet_row.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:boorusphere/utils/number_format.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens the description of [tag] as answered by [server].
///
/// The sheet is read-only: it reports what the engine publishes and never asks
/// for an account of its own. A server whose engine has no observed tag
/// endpoint says so instead of guessing at one.
Future<void> showTagInfoSheet(
  BuildContext context, {
  required Server server,
  required String tag,
}) {
  return showSheet<void>(
    context: context,
    builder: (context) => _TagInfoSheet(server: server, tag: tag),
  );
}

class _TagInfoSheet extends ConsumerWidget {
  const _TagInfoSheet({required this.server, required this.tag});

  final Server server;
  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = TagInfoQuery(serverId: server.id, tag: tag);
    final info = ref.watch(tagInfoProvider(query));

    return SheetShell(
      // The tag itself is what the sheet is about; a generic "Tag info"
      // header would repeat the same fact in weaker words.
      title: tag,
      footer: info.hasError && info.error != BooruError.tagInfoUnsupported
          ? SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  // Retry means ask the server again, not replay the answer
                  // the cache is about to hand back.
                  ref.read(tagInfoCacheProvider).remove(server.id, tag);
                  ref.invalidate(tagInfoProvider(query));
                },
                child: Text(context.t.retry),
              ),
            )
          : null,
      child: SingleChildScrollView(
        child: info.when(
          loading: () => Semantics(
            label: context.t.tagInfo.loading,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: DesignTokens.spacingXl),
              child: Center(
                child: SizedBox.square(
                  dimension: DesignTokens.spacingLg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
          error: (error, _) => _Notice(message: _errorMessage(context, error)),
          data: (info) => info.hasDetails
              ? _InfoPanel(info: info)
              : _Notice(
                  message: context.t.tagInfo.unknown(serverName: server.name),
                ),
        ),
      ),
    );
  }

  String _errorMessage(BuildContext context, Object error) {
    if (error == BooruError.tagInfoUnsupported) {
      return context.t.tagInfo.unsupported;
    }
    if (error == BooruError.unparsable) {
      return context.t.tagInfo.unknown(serverName: server.name);
    }
    return context.t.tagInfo.unavailable(serverName: server.name);
  }
}

/// The facts a tag sheet can carry, in the order a reader scans them.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.info});

  final TagInfo info;

  @override
  Widget build(BuildContext context) {
    final category = _categoryName(context, info.category);
    final related = info.related.map((it) => it.name).join(', ');
    final prose = context.theme.textTheme.bodyMedium;

    return SheetPanel(
      children: [
        if (category != null)
          SheetFactRow(label: context.t.tagInfo.category, value: category),
        if (info.postCount case final count?)
          SheetFactRow(
            label: context.t.tagInfo.posts,
            value: compactCount(count),
          ),
        if (info.wiki.isNotEmpty)
          SheetBlock(
            label: context.t.tagInfo.wiki,
            child: Text(info.wiki, style: prose),
          ),
        if (info.aliases.isNotEmpty)
          SheetBlock(
            label: context.t.tagInfo.aliases,
            child: Text(info.aliases.join(', '), style: prose),
          ),
        if (related.isNotEmpty)
          SheetBlock(
            label: context.t.tagInfo.related,
            child: Text(related, style: prose),
          ),
      ],
    );
  }

  /// The category in the same words the tag groups use, so the sheet and the
  /// post panel name the same thing the same way.
  String? _categoryName(BuildContext context, TagCategory? category) {
    return switch (category) {
      TagCategory.artist => context.t.artist,
      TagCategory.copyright => context.t.copyright,
      TagCategory.character => context.t.character,
      TagCategory.general => context.t.general,
      TagCategory.meta => context.t.meta,
      null => null,
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: NoticeCard(
        icon: const Icon(Icons.info_outline, size: DesignTokens.iconChipSize),
        children: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextRoles.of(context).rowTitle,
        ),
      ),
    );
  }
}
