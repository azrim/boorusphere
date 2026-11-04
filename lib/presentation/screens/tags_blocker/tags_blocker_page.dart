import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/tags_blocker/tag_expression.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/field_decoration.dart';
import 'package:boorusphere/presentation/widgets/in_block_note.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:boorusphere/presentation/widgets/sectioned_list.dart';
import 'package:boorusphere/presentation/widgets/tile_group.dart';
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

    void submit(String value) {
      // The whole line is one entry: spaces are the AND operator inside an
      // expression, not a separator between entries. Submit again for another
      // entry.
      final expression = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (expression.isEmpty) return;
      if (parseBlockedTagExpressions([expression]).isEmpty) return;
      ref
          .read(tagsBlockerStateProvider.notifier)
          .push(tag: expression.toLowerCase());
      controller.clear();
    }

    return SectionedList(
      children: [
        // Neither block carries a heading: the add-expression field and the list
        // it feeds say what they are, so the gap a heading would have made is
        // added by hand instead.
        const SizedBox(height: DesignTokens.spacingLg),
        SectionSurface(
          children: [
            InBlockNote(text: context.t.tagsBlocker.desc),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingCardInset,
                0,
                DesignTokens.spacingCardInset,
                DesignTokens.spacingSm,
              ),
              child: TextField(
                controller: controller,
                enableIMEPersonalizedLearning: !imeIncognito,
                onSubmitted: submit,
                textInputAction: TextInputAction.done,
                decoration:
                    flatFieldDecoration(
                      context,
                      label: context.t.tagsBlocker.add,
                      hint: context.t.tagsBlocker.hint,
                    ).copyWith(
                      // A field whose only way in is the keyboard's done key
                      // loses whatever was typed when the reader taps away.
                      suffixIcon: IconButton(
                        onPressed: () => submit(controller.text),
                        tooltip: context.t.add,
                        icon: const Icon(Icons.add),
                      ),
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        if (blockedTags.isEmpty)
          NoticeCard(
            // A notice is a block like the one above it, so it takes the page
            // gutter and adds no card margin on top of it.
            margin: EdgeInsets.zero,
            icon: const Icon(Icons.tag),
            children: Text(
              context.t.tagsBlocker.empty,
              textAlign: TextAlign.center,
              style: AppTextRoles.of(context).rowTitle,
            ),
          )
        else
          TileGroup(
            children: [
              for (final tag in blockedTags.entries)
                ListTile(
                  title: Text(tag.value.name),
                  leading: const Icon(Icons.block),
                  trailing: IconButton(
                    tooltip: context.t.remove,
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
      ],
    );
  }
}
