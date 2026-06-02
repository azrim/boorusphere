import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/download_dialog.dart';
import 'package:boorusphere/utils/extensions/number.dart';
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
      color: Colors.white,
      icon: const Icon(Icons.find_in_page_outlined),
      tooltip: context.t.findRelated,
      onPressed: () {
        final newSession = SearchSession(serverId: session, query: query);
        context.router.push(HomeRoute(session: newSession));
      },
    );
  }
}

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
    final viewPadding = context.mediaQuery.viewPadding;
    final safePaddingBottom = useState(viewPadding.bottom);
    if (viewPadding.bottom > safePaddingBottom.value) {
      safePaddingBottom.value = viewPadding.bottom;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      height: safePaddingBottom.value + 86,
      alignment: Alignment.bottomRight,
      padding: EdgeInsets.only(bottom: safePaddingBottom.value + 8, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
      color: Colors.white,
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
    return IconButton(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      color: Colors.white,
      icon: const Icon(Icons.link_outlined),
      onPressed: () => launchUrlString(
        post.originalFile,
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

class PostFavoriteButton extends HookConsumerWidget {
  const PostFavoriteButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritePostStateProvider);
    final animator = useAnimationController(
      duration: const Duration(milliseconds: 300),
    );
    final animation = useAnimation(
      ColorTween(
        begin: Colors.white,
        end: Theme.of(context).colorScheme.error,
      ).animate(animator),
    );
    final isFav = favorites.contains(post);
    isFav ? animator.forward() : animator.reverse();

    return IconButton(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      color: Colors.white,
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
    );
  }
}

class PostDownloadButton extends HookConsumerWidget {
  const PostDownloadButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(downloadEntryStateProvider).getByPost(post);
    final progress = ref.watch(downloadProgressStateProvider).getById(entry.id);
    final pending = useState(false);

    return Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: pending.value
              ? null
              : progress.status.isDownloading
              ? progress.progress.ratio
              : 0,
        ),
        IconButton(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          color: Colors.white,
          icon: Icon(
            progress.status.isDownloaded ? Icons.download_done : Icons.download,
          ),
          onPressed:
              pending.value ||
                  progress.status.isDownloaded ||
                  progress.status.isDownloading
              ? null
              : () async {
                  pending.value = true;
                  await DownloaderDialog.show(context, ref, post);
                  pending.value = false;
                },
          disabledColor: context.colorScheme.primary,
        ),
      ],
    );
  }
}
