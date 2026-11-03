import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/changelog_state.dart';
import 'package:boorusphere/presentation/screens/about/changelog_page.dart';
import 'package:boorusphere/presentation/theme/app_typography.dart';
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
            // A release with no written notes still has to say so: an empty
            // panel read as a sheet that failed to draw its content.
            data: (data) => data.isEmpty
                ? _Notice(
                    icon: const Icon(Icons.event_note_outlined),
                    message: context.t.changelog.none,
                  )
                : ChangelogDataView(changelog: data.first, showVersion: false),
            // The notes ship inside the app, so a failure here means there is
            // nothing to read and no retry that could change it: the same
            // notice the empty release gets, with a different mark.
            error: (e, s) => _Notice(
              icon: const Icon(Icons.cancel_rounded),
              message: context.t.changelog.none,
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

/// One line of bad news inside the sheet, in the shared notice block with the
/// title role every other empty state uses.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final Widget icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return NoticeCard(
      icon: icon,
      children: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTextRoles.of(context).rowTitle,
      ),
    );
  }
}
