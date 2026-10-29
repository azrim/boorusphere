import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/changelog_state.dart';
import 'package:boorusphere/presentation/screens/about/changelog_page.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class WhatsNewBottomSheet extends HookConsumerWidget {
  const WhatsNewBottomSheet({super.key});

  static void show(BuildContext context) {
    showSheet<void>(
      context: context,
      builder: (_) => const WhatsNewBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envRepo = ref.read(envRepoProvider);

    final changelog = ref.watch(
      changelogStateProvider(ChangelogType.assets, envRepo.appVersion),
    );

    return SheetShell(
      title: context.t.changelog.whatsNew(version: envRepo.appVersion),
      maxHeightFactor: 0.9,
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(DesignTokens.controlHeightMin),
          ),
          onPressed: context.navigator.pop,
          child: Text(context.t.actionContinue),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: DesignTokens.spacingSm,
          ),
          child: changelog.when(
            data: (data) => data.isEmpty
                ? const SizedBox.shrink()
                : ChangelogDataView(changelog: data.first, showVersion: false),
            error: (e, s) => NoticeCard(
              icon: const Icon(Icons.cancel_rounded),
              children: Text(context.t.changelog.none),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(DesignTokens.spacingXl),
              child: Center(child: RefreshProgressIndicator()),
            ),
          ),
        ),
      ),
    );
  }
}
