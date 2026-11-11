import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/app_media_chrome.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/app_toast.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/utils/extensions/number.dart';
import 'package:boorusphere/utils/url_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PostRelatedButton extends StatelessWidget {
  const PostRelatedButton({
    super.key,
    required this.post,
    required this.session,
  });

  final Post post;
  final String session;

  @override
  Widget build(BuildContext context) {
    // Extract top tags from the post - prefer artist, character, copyright tags
    // as they're most relevant for finding related content
    final tags = [
      ...post.tagsArtist.take(2),
      ...post.tagsCharacter.take(2),
      ...post.tagsCopyright.take(2),
      ...post.tagsGeneral.take(3),
    ];

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final query = tags.join(' ');

    return IconButton(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      color: AppMediaChrome.of(context).foreground,
      icon: const Icon(Icons.find_in_page_outlined),
      tooltip: context.t.findRelated,
      onPressed: () {
        final newSession = SearchSession(serverId: session, query: query);
        context.router.push(HomeRoute(session: newSession));
      },
    );
  }
}

/// The height of the scrim band the controls sit in: one control row (56 dp, a
/// 24 dp glyph plus the 16 dp padding each button asks for) with room above it
/// for the gradient to fade through. The bar grows past this floor when the
/// row has to wrap, which is what a fixed height used to clip instead.
const double _kToolboxBandHeight = 86.0;

class PostToolbox extends HookConsumerWidget {
  const PostToolbox(this.post, {super.key, this.onShowDetails, this.session});

  final Post post;

  /// Session used for navigation to related posts search.
  /// If null, related posts button won't be shown.
  final String? session;

  /// Optional callback wired by the post viewer to expand the details sheet.
  /// When non-null, a details icon button is rendered as part of the row.
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Aspect-scoped: only inset changes rebuild this bar, not every
    // MediaQuery change (keyboard frames, brightness, locale).
    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Latched so the bar keeps its clearance once immersive mode reports a
    // zero inset. The latch is updated in an effect so build stays free of
    // state writes.
    final safePaddingBottom = useState(viewPadding.bottom);
    useEffect(() {
      if (viewPadding.bottom > safePaddingBottom.value) {
        safePaddingBottom.value = viewPadding.bottom;
      }
      return null;
    }, [viewPadding.bottom]);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppMediaChrome.of(context).scrim, Colors.transparent],
        ),
      ),
      constraints: BoxConstraints(
        minHeight: safePaddingBottom.value + _kToolboxBandHeight,
      ),
      alignment: Alignment.bottomRight,
      // Left/right insets matter in landscape, where a cutout can sit under
      // the trailing button.
      padding: EdgeInsets.only(
        left: viewPadding.left + DesignTokens.spacingSm,
        right: viewPadding.right + DesignTokens.spacingSm,
        bottom: safePaddingBottom.value + DesignTokens.spacingSm,
      ),
      // A wrap, not a row: five controls do not always fit one run in
      // landscape, and a second run costs nothing in portrait.
      child: Wrap(
        alignment: WrapAlignment.end,
        children: [
          if (onShowDetails != null)
            PostDetailsButton(onPressed: onShowDetails!),
          PostFavoriteButton(
            key: ValueKey('fav_${post.id}_${post.serverId}'),
            post: post,
          ),
          PostDownloadButton(
            key: ValueKey('dl_${post.id}_${post.serverId}'),
            post: post,
          ),
          if (session != null) PostRelatedButton(post: post, session: session!),
          PostOpenLinkButton(post: post),
        ],
      ),
    );
  }
}

class PostDetailsButton extends StatelessWidget {
  const PostDetailsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      color: AppMediaChrome.of(context).foreground,
      icon: const Icon(Icons.info_outline),
      tooltip: context.t.details,
      onPressed: onPressed,
    );
  }
}

class PostOpenLinkButton extends StatelessWidget {
  const PostOpenLinkButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    // An unsafe address used to leave a live-looking button that swallowed the
    // tap. The guard now decides the control's state, so a link the app will
    // not open reads as closed before it is pressed.
    final openable = isSafeUrl(post.originalFile);

    return IconButton(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      color: AppMediaChrome.of(context).foreground,
      tooltip: context.t.viewer.openLink,
      icon: const Icon(Icons.link_outlined),
      onPressed: openable
          ? () => launchUrlString(
              post.originalFile,
              mode: LaunchMode.externalApplication,
            )
          : null,
    );
  }
}

class PostFavoriteButton extends HookConsumerWidget {
  const PostFavoriteButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the list keeps the button in step with saves and removals made
    // elsewhere; the predicate below then reads that list.
    ref.watch(favoritePostStateProvider);
    final chrome = AppMediaChrome.of(context);
    final animator = useAnimationController(
      duration: context.motionDuration(DesignTokens.durationNormal),
    );
    final animation = useAnimation(
      ColorTween(
        begin: chrome.foreground,
        end: Theme.of(context).colorScheme.error,
      ).animate(animator),
    );
    final isFav = ref.read(favoritePostStateProvider.notifier).isFavorite(post);
    useEffect(() {
      if (isFav) {
        animator.forward();
      } else {
        animator.reverse();
      }
      return null;
    }, [isFav]);

    return Semantics(
      // The filled/outline icon is the only visual cue, so the state has to be
      // announced as well as the name.
      toggled: isFav,
      child: IconButton(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        color: chrome.foreground,
        tooltip: isFav
            ? context.t.postAction.unfavorite
            : context.t.postAction.favorite,
        icon: isFav
            ? Icon(Icons.favorite, color: animation)
            : Icon(Icons.favorite_border, color: animation),
        onPressed: () {
          if (isFav) {
            ref.read(favoritePostStateProvider.notifier).remove(post);
          } else {
            ref.read(favoritePostStateProvider.notifier).save(post);
          }
        },
      ),
    );
  }
}

class PostDownloadButton extends HookConsumerWidget {
  const PostDownloadButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Both lists are watched: the entry a control acts on is chosen from the
    // progress timestamps, so a row that gains a newer timestamp has to
    // reselect even when the entry list itself did not change.
    final entries = ref.watch(downloadEntryStateProvider);
    final progresses = ref.watch(downloadProgressStateProvider);
    final entry = entries.getByPost(post, progressOf: progresses.getById);
    final progress = progresses.getById(entry.id);
    final pending = useState(false);
    // The record outlives the file: a download whose file was removed outside
    // the app must still be startable from here.
    final isDownloaded =
        progress.status.isDownloaded &&
        ref.watch(sharedStorageHandleProvider).fileExists(entry.dest);
    // A queued or running download is still the only thing this control can
    // act on: the entry lives behind it, so a task that never settles would
    // otherwise leave the button disabled with no way back.
    final inFlight = progress.status.isDownloading || progress.status.isPending;
    final progressLabel = progress.progress >= 0
        ? ' ${progress.progress}%'
        : '';
    final label = isDownloaded
        ? context.t.downloads.status.downloaded
        : inFlight
        ? '${context.t.downloads.status.downloading}$progressLabel'
        : context.t.postAction.download;

    return Stack(
      alignment: Alignment.center,
      children: [
        // The ring is decorative; the button carries the label and the
        // progress readout.
        ExcludeSemantics(
          child: CircularProgressIndicator(
            value:
                pending.value ||
                    (progress.status.isDownloading && progress.progress < 0)
                ? null
                : progress.status.isDownloading
                ? progress.progress.ratio
                : 0,
          ),
        ),
        IconButton(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          color: AppMediaChrome.of(context).foreground,
          tooltip: inFlight ? context.t.cancel : label,
          icon: Icon(isDownloaded ? Icons.download_done : Icons.download),
          onPressed: pending.value || isDownloaded
              ? null
              : () async {
                  if (inFlight) {
                    await ref.read(downloaderProvider).cancel(id: entry.id);
                    return;
                  }

                  pending.value = true;
                  try {
                    final started = await DownloaderDialog.show(
                      context,
                      ref,
                      post,
                    );
                    if (started == false && context.mounted) {
                      showToast(context, context.t.downloads.failedToStart);
                    }
                  } finally {
                    // The dialog does not mute the viewer behind it: a
                    // slideshow step can change the page while it is open,
                    // and this button dies with its page. The notifier is
                    // disposed then, so only a still-mounted button clears
                    // its own pending state.
                    if (context.mounted) pending.value = false;
                  }
                },
          // A control that ignores the tap must not wear the accent that
          // means "this is the live action". The disabled tone comes from the
          // media role set, not the scheme's own `onSurface`, because a light
          // palette would hand a dark grey to a glyph sitting on black scrim.
          disabledColor: AppMediaChrome.of(context).foregroundDisabled,
        ),
      ],
    );
  }
}
