import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/changelog/entity/changelog_data.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/changelog_state.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/empty_state.dart';
import 'package:boorusphere/presentation/widgets/section_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class ChangelogPage extends ConsumerWidget {
  const ChangelogPage({super.key, required this.type, this.version});

  final ChangelogType type;
  final AppVersion? version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changelog = ref.watch(changelogStateProvider(type, version));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          version == null
              ? context.t.changelog.title
              : changelog.maybeWhen(
                  data: (value) => context.t.version(version: '$version'),
                  orElse: () => context.t.changelog.title,
                ),
        ),
      ),
      body: SafeArea(
        child: changelog.when(
          data: (data) => data.length == 1
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingMd,
                  ),
                  child: ChangelogDataView(
                    changelog: data.first,
                    showVersion: false,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingMd,
                  ),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    return ChangelogDataView(changelog: data[index]);
                  },
                ),
          // A changelog that could not be fetched is an answer, not a wait:
          // the notice offers the retry instead of leaving the page stuck.
          error: (e, s) => EmptyState(
            icon: const Icon(Icons.cancel_rounded),
            title: context.t.changelog.none,
            action: FilledButton(
              onPressed: () =>
                  ref.invalidate(changelogStateProvider(type, version)),
              child: Text(context.t.retry),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class ChangelogDataView extends StatelessWidget {
  const ChangelogDataView({
    super.key,
    required this.changelog,
    this.showVersion = true,
  });

  final ChangelogData changelog;
  final bool showVersion;
  @override
  Widget build(BuildContext context) {
    // Each entry is already one bullet, so hand them to markdown as a list.
    // Joining them as plain lines would collapse the whole version into a
    // single paragraph.
    final textContent = changelog.logs
        .map((it) => '- ${it.replaceAll('\n', '\n  ')}')
        .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showVersion)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacingXs,
              DesignTokens.spacingLg,
              DesignTokens.spacingXs,
              DesignTokens.spacingSm,
            ),
            child: Text(
              '${changelog.version}',
              style: context.theme.textTheme.titleLarge,
            ),
          ),
        // The notes are a block like any other: the same container tone and
        // hairline the rest of the app groups content with.
        SectionSurface(
          children: [
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingCardInset),
              child: MarkdownBody(
                data: textContent,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(height: 1.5),
                  listBullet: const TextStyle(height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
