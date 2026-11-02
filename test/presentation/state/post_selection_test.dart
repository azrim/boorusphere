import 'package:boorusphere/presentation/provider/post_selection_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('retainAll drops every id that left the visible feed', () {
    final container = _container();
    final notifier = container.read(postSelectionProvider.notifier)
      ..select(1)
      ..select(2)
      ..select(3);

    notifier.retainAll({1, 3, 4});

    expect(container.read(postSelectionProvider), {1, 3});
    expect(notifier.count, 2);
  });

  test('retainAll leaves a still-visible selection untouched', () {
    final container = _container();
    final notifier = container.read(postSelectionProvider.notifier)..select(1);
    final before = container.read(postSelectionProvider);

    var emissions = 0;
    container.listen(postSelectionProvider, (_, _) => emissions++);
    notifier.retainAll({1, 2});

    // Same set instance: a prune that drops nothing must not rebuild the
    // timeline that listens to it.
    expect(container.read(postSelectionProvider), same(before));
    expect(emissions, 0);
  });

  test('retainAll on an empty selection does not emit', () {
    final container = _container();
    var emissions = 0;
    container.listen(postSelectionProvider, (_, _) => emissions++);

    container.read(postSelectionProvider.notifier).retainAll({1});

    expect(container.read(postSelectionProvider), isEmpty);
    expect(emissions, 0);
  });
}
