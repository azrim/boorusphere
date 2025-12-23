import 'package:boorusphere/presentation/screens/home/search/search_bar.dart';
import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search/search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchScreen extends HookConsumerWidget {
  const SearchScreen({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchBar = ref.watch(searchBarControllerProvider);
    final isOpen = searchBar.isOpen;
    final animator =
        useAnimationController(duration: const Duration(milliseconds: 300));
    final animation =
        CurvedAnimation(parent: animator, curve: Curves.easeInOutCubic);

    useEffect(() {
      isOpen ? animator.forward() : animator.reverse();
    }, [isOpen]);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        FadeTransition(
          opacity: Tween<double>(
            begin: 0.5,
            end: 1,
          ).animate(animation),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: const Offset(0, 0),
            ).animate(animation),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                // Close search bar on swipe down with sufficient velocity
                final velocity = details.velocity.pixelsPerSecond.dy;
                if (velocity > 200) {
                  searchBar.close();
                }
              },
              onVerticalDragUpdate: (details) {
                // Close search bar if user drags down significantly
                final delta = details.delta.dy;
                if (delta > 15) {
                  searchBar.close();
                }
              },
              onTap: () {
                // Prevent taps from closing when interacting with suggestions
                // This is handled by individual suggestion items
              },
              child: const SearchSuggestion(),
            ),
          ),
        ),
        HomeSearchBar(scrollController: scrollController),
      ],
    );
  }
}
