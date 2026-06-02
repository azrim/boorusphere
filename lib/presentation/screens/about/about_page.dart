import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/changelog/entity/changelog_data.dart';
import 'package:boorusphere/data/repository/version/app_version_repo.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:boorusphere/presentation/provider/changelog_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/about/changelog_page.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/utils/extensions/number.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

@RoutePage()
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersions = ref.watch(appVersionsStateProvider);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colorScheme.primaryContainer,
                ),
                padding: const EdgeInsets.all(DesignTokens.spacingXl),
                margin: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
                child: Image.asset(
                  'assets/icons/exported/logo.png',
                  height: 48,
                  color: context.colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                'Boorusphere',
                style: context.theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: appVersions.maybeWhen(
                  data: (data) {
                    return Text(
                      context.t.version(version: '${data.current} - $kAppArch'),
                      style: context.theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    );
                  },
                  orElse: SizedBox.shrink,
                ),
              ),
              appVersions.when(
                data: (data) {
                  return data.latest.isNewerThan(data.current)
                      ? _Updater(data.latest)
                      : ElevatedButton.icon(
                          onPressed: () {
                            ref.invalidate(appVersionsStateProvider);
                          },
                          style: ElevatedButton.styleFrom(elevation: 0),
                          icon: const Icon(Icons.done),
                          label: Text(context.t.updater.onLatest),
                        );
                },
                loading: () {
                  return ElevatedButton.icon(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(elevation: 0),
                    icon: Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(),
                    ),
                    label: Text(context.t.updater.checking),
                  );
                },
                error: (e, s) {
                  return ElevatedButton.icon(
                    onPressed: () {
                      ref.invalidate(appVersionsStateProvider);
                    },
                    style: ElevatedButton.styleFrom(elevation: 0),
                    icon: const Icon(Icons.update),
                    label: Text(context.t.updater.check),
                  );
                },
              ),
              const Divider(height: DesignTokens.spacingXl),
              ListTile(
                title: Text(context.t.changelog.title),
                leading: const Icon(Icons.list_alt_rounded),
                onTap: () {
                  context.router.push(
                    ChangelogRoute(type: ChangelogType.assets),
                  );
                },
              ),
              ListTile(
                title: Text(context.t.github),
                leading: const FaIcon(FontAwesomeIcons.github),
                onTap: () {
                  launchUrlString(
                    AppVersionRepo.gitUrl,
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                title: Text(context.t.ossLicense),
                leading: const Icon(Icons.collections_bookmark),
                onTap: () {
                  context.router.push(const LicensesRoute());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Updater extends StatelessWidget {
  const _Updater(this.data);

  final AppVersion data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(context.t.updater.onNewVersion),
        ),
        // Inline changelog for the new version. Sourced via
        // ChangelogType.git so the pre-release CHANGELOG.md changes for
        // an unreleased version (e.g. when CI delivers an APK to
        // Telegram before the GitHub Release exists) are still
        // surfaced. Falls back to a silent no-op if the network fetch
        // returns empty / errors — the user can still tap Download.
        _InlineChangelog(version: data),
        _Downloader(data),
      ],
    );
  }
}

/// Compact, scrollable card-style changelog rendered inline in the
/// updater flow. Uses the existing [ChangelogDataView] for rendering
/// so visuals stay consistent with the full-screen ChangelogPage.
class _InlineChangelog extends ConsumerWidget {
  const _InlineChangelog({required this.version});

  final AppVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changelog = ref.watch(
      changelogStateProvider(ChangelogType.git, version),
    );

    return changelog.when(
      data: (entries) {
        if (entries.isEmpty || entries.first == ChangelogData.empty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: context.colorScheme.surfaceContainerHighest,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: ChangelogDataView(
                  changelog: entries.first,
                  showVersion: false,
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _Downloader extends ConsumerWidget {
  const _Downloader(this.version);

  final AppVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(appUpdateProgressProvider);
    final hasUpdateApk = progress.status.isDownloaded;

    final showDownloadButton =
        progress.status.isCanceled ||
        progress.status.isFailed ||
        progress.status.isEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!hasUpdateApk && showDownloadButton)
          ElevatedButton(
            onPressed: () {
              checkNotificationPermission(context).then((hasPerm) {
                if (hasPerm) {
                  ref.read(appUpdaterProvider).start(version);
                }
              });
            },
            style: ElevatedButton.styleFrom(elevation: 0),
            child: Text(context.t.updater.download(version: version)),
          ),
        if (progress.status.isDownloading) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${progress.progress}%', textAlign: TextAlign.end),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LinearProgressIndicator(
                value: progress.progress.ratio,
                minHeight: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              ref.read(appUpdaterProvider).clear();
            },
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 16),
        ],
        if (hasUpdateApk)
          ElevatedButton(
            onPressed: () {
              ref.watch(appUpdaterProvider).install(version);
            },
            child: Text(context.t.updater.install),
          ),
      ],
    );
  }
}
