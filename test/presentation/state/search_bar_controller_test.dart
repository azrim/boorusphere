import 'package:boorusphere/presentation/screens/home/search/search_bar_controller.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _session = SearchSession(serverId: 'S', query: 'cat_ear');

void main() {
  late ProviderContainer container;
  late SearchBarController controller;

  setUp(() {
    container = ProviderContainer();
    // The provider is auto-dispose: without a listener the controller would be
    // gone before the test could use it.
    container.listen(searchBarControllerProvider(_session), (_, _) {});
    controller = container.read(searchBarControllerProvider(_session));
  });

  tearDown(() => container.dispose());

  test('several picked tags are appended in the order they were picked', () {
    controller.appendTags(['touhou', 'cat', 'solo']);

    expect(controller.value, 'cat_ear touhou cat solo ');
  });

  test('a tag already in the query is not added twice', () {
    controller.appendTags(['touhou', 'CAT_EAR', 'touhou']);

    expect(controller.value, 'cat_ear touhou ');
  });
}
