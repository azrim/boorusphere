import 'package:boorusphere/data/repository/fallback_box.dart';
import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:flutter_test/flutter_test.dart';

import '../utils/hive.dart';

void main() {
  final hiveContainer = HiveTestContainer();

  tearDownAll(() async {
    await hiveContainer.dispose();
  });

  group('fallback box', () {
    test('has no stand-in for a box that opened normally', () {
      expect(fallbackFor<BooruTag>('blockedTags'), isNull);
    });

    test('registers an empty stand-in of the same type', () async {
      await openFallbackBox<BooruTag>('blockedTags');

      final box = fallbackFor<BooruTag>('blockedTags');
      expect(box, isNotNull);
      expect(box!.isEmpty, isTrue);
      expect(box.name, isNot('blockedTags'));
    });

    test('answers only for the type the stand-in was opened with', () async {
      await openFallbackBox<BooruTag>('blockedTags');

      expect(fallbackFor<FavoritePost>('blockedTags'), isNull);
    });

    test('reuses the stand-in for the same box', () async {
      await openFallbackBox<BooruTag>('blockedTags');
      final first = fallbackFor<BooruTag>('blockedTags');

      await openFallbackBox<BooruTag>('blockedTags');
      expect(fallbackFor<BooruTag>('blockedTags'), same(first));
    });
  });
}
