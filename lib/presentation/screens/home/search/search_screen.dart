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
    final canBeDragged = useState(false);
    final screenHeight = MediaQuery.of(context).size.height;

    useEffect(() {
      isOpen ? animator.forward() : animator.reverse();
    }, [isOpen]);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (details) {
            // Only allow dragging when search is open
            canBeDragged.value = isOpen;
          },
          onVerticalDragUpdate: (details) {
            if (!canBeDragged.value) return;

            final delta = details.primaryDelta;
            if (delta == null) return;

            // Only allow downward drag (positive delta)
            if (delta > 0) {
              // Update animation value based on drag distance
              animator.value -= delta / (screenHeight * 0.3);
              animator.value = animator.value.clamp(0.0, 1.0);
            }
          },
          onVerticalDragEnd: (details) async {
            if (!canBeDragged.value) return;

            final velocity = details.velocity.pixelsPerSecond.dy;

            if (velocity > 300 || animator.value < 0.7) {
              // Close search bar
              await animator.reverse();
              searchBar.close();
            } else {
              // Snap back to open
              await animator.forward();
            }
          },
          onTap: () {
            // Prevent taps from closing when interacting with suggestions
            // This is handled by individual suggestion items
          },
          child: FadeTransition(
            opacity: Tween<double>(
              begin: 0.5,
              end: 1,
            ).animate(animation),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: const Offset(0, 0),
              ).animate(animation),
              child: const SearchSuggestion(),
            ),
          ),
        ),
        HomeSearchBar(scrollController: scrollController),
      ],
    );
  }
}
