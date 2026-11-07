import 'package:boorusphere/presentation/screens/home/search/search_bar.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search/search_suggestion.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final searchBar = ref.watch(searchBarControllerProvider(session));
    final isOpen = searchBar.isOpen;
    final animator = useAnimationController(
      duration: context.motionDuration(DesignTokens.durationNormal),
    );
    // The controller outlives every build, so its curve wrapper has to as well:
    // one created here attached a status listener per rebuild and never
    // removed it.
    final animation = useMemoized(
      () =>
          CurvedAnimation(parent: animator, curve: DesignTokens.curveStandard),
      [animator],
    );
    useEffect(() => animation.dispose, [animation]);

    useEffect(() {
      isOpen ? animator.forward() : animator.reverse();
    }, [isOpen]);

    // The panel is a full screen of blur, a scroll view and up to twenty-five
    // rows; once closed it is only off-screen, so it is taken out of the tree.
    // Mounted on open, unmounted after the reverse settles. The scroll
    // controller is owned here so the list comes back where it was.
    final dismissed = useListenableSelector(
      animator,
      () => animator.isDismissed,
    );
    final scrollController = useScrollController();

    // The slot is full-screen and the bar is aligned to its bottom edge, so
    // the screen has to claim that height itself: with the panel unmounted
    // while closed, a loose stack shrank to the bar and the shell centred it
    // in the middle of the page.
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (isOpen || !dismissed)
            FadeTransition(
              opacity: Tween<double>(begin: 0.5, end: 1).animate(animation),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: const Offset(0, 0),
                ).animate(animation),
                child: SearchSuggestion(
                  animator: animator,
                  searchBar: searchBar,
                  scrollController: scrollController,
                ),
              ),
            ),
          const HomeSearchBar(),
        ],
      ),
    );
  }
}
