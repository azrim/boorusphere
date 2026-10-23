import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class TagsBlockerPage extends StatelessWidget {
  const TagsBlockerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.tagsBlocker.title)),
      body: const SafeArea(child: _TagsBlockerContent()),
    );
  }
}

class _TagsBlockerContent extends HookConsumerWidget {
  const _TagsBlockerContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedTags = ref.watch(tagsBlockerStateProvider);
    final controller = useTextEditingController();
    final imeIncognito = ref.watch(
      uiSettingStateProvider.select((it) => it.imeIncognito),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
      children: [
        const SizedBox(height: DesignTokens.spacingMd),
        SectionSurface(
          children: [
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingCardInset,
                      vertical: DesignTokens.spacingXs,
                    ),
                    child: Text(
                      context.t.tagsBlocker.desc,
                      style: context.theme.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingSm),
                  TextField(
                    controller: controller,
                    enableIMEPersonalizedLearning: !imeIncognito,
                    onSubmitted: (value) {
                      final values = value.toWordList();
                      ref
                          .read(tagsBlockerStateProvider.notifier)
                          .pushAll(tags: values);
                      controller.clear();
                    },
                    decoration: flatFieldDecoration(
                      context,
                      label: context.t.tagsBlocker.hint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        if (blockedTags.isEmpty)
          NoticeCard(
            icon: const Icon(Icons.tag),
            children: Text(context.t.tagsBlocker.empty),
          )
        else
          TileGroup(
            children: [
              for (final tag in blockedTags.entries)
                ListTile(
                  title: Text(tag.value.name),
                  leading: const Icon(Icons.block),
                  trailing: IconButton(
                    onPressed: () {
                      ref
                          .read(tagsBlockerStateProvider.notifier)
                          .delete(tag.key);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        const SizedBox(height: DesignTokens.spacingLg),
      ],
    );
  }
}
