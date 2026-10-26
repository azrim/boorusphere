import 'package:boorusphere/data/repository/booru/entity/raw_post.dart';
import 'package:boorusphere/data/repository/booru/utils/post_pipeline.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:flutter_test/flutter_test.dart';

const _server = Server(
  id: 'Test',
  homepage: 'https://example.com',
  postUrl: 'post/{post-id}',
);

List<String> _strings(Object? value) =>
    (value as List?)?.cast<String>() ?? const [];

RawPost _mapEntry(Map<String, dynamic> entry) {
  return RawPost(
    id: entry['id'] as int? ?? -1,
    originalFile: entry['originalFile'] as String? ?? '',
    previewFile: entry['previewFile'] as String? ?? '',
    sampleFile: entry['sampleFile'] as String? ?? '',
    width: entry['width'] as int? ?? -1,
    height: entry['height'] as int? ?? -1,
    sampleWidth: entry['sampleWidth'] as int? ?? -1,
    sampleHeight: entry['sampleHeight'] as int? ?? -1,
    previewWidth: entry['previewWidth'] as int? ?? -1,
    previewHeight: entry['previewHeight'] as int? ?? -1,
    rating: entry['rating'] as String? ?? '',
    source: entry['source'] as String? ?? '',
    score: entry['score'] as int? ?? 0,
    tags: _strings(entry['tags']),
    tagsArtist: _strings(entry['tagsArtist']),
    tagsCharacter: _strings(entry['tagsCharacter']),
    tagsCopyright: _strings(entry['tagsCopyright']),
    tagsGeneral: _strings(entry['tagsGeneral']),
    tagsMeta: _strings(entry['tagsMeta']),
  );
}

Map<String, dynamic> _validEntry({
  int id = 1,
  String originalFile = 'https://cdn.example.com/a.png',
  String previewFile = 'https://cdn.example.com/a-thumb.png',
  int width = 100,
  int height = 200,
}) {
  return {
    'id': id,
    'originalFile': originalFile,
    'previewFile': previewFile,
    'width': width,
    'height': height,
  };
}

void main() {
  group('buildPosts', () {
    test('skips entries that fail the file/content guard', () {
      final posts = buildPosts(_server, [
        _validEntry(id: 1, originalFile: ''),
        _validEntry(id: 2, previewFile: ''),
        _validEntry(id: 3, width: 0),
        _validEntry(id: 4, height: 0),
        _validEntry(id: 5),
      ], _mapEntry);

      expect(posts.map((it) => it.id), [5]);
    });

    test('rawCount keeps the entries the guard rejected', () {
      final page = buildPosts(_server, [
        _validEntry(id: 1, originalFile: ''),
        _validEntry(id: 2),
      ], _mapEntry);

      expect(page.posts, hasLength(1));
      // Pagination compares rawCount against the page size, so a page that
      // lost an entry is not mistaken for the end of the results.
      expect(page.rawCount, 2);
    });

    test('de-duplicates by id, keeping the first guard-passing entry', () {
      final posts = buildPosts(_server, [
        _validEntry(id: 1, originalFile: 'https://cdn.example.com/first.png'),
        _validEntry(id: 1, originalFile: 'https://cdn.example.com/second.png'),
      ], _mapEntry);

      expect(posts, hasLength(1));
      expect(posts.single.originalFile, 'https://cdn.example.com/first.png');
    });

    test('a guard-failing entry does not consume its id slot', () {
      // Regression: the previous "mark before guard" de-dup dropped the later
      // valid entry that shared an id with a discarded one.
      final posts = buildPosts(_server, [
        _validEntry(id: 7, width: 0, height: 0),
        _validEntry(id: 7),
      ], _mapEntry);

      expect(posts, hasLength(1));
      expect(posts.single.id, 7);
    });

    test('de-duplicates missing ids collapsed to -1', () {
      final posts = buildPosts(_server, [
        _validEntry(id: -1),
        _validEntry(id: -1),
      ], _mapEntry);

      expect(posts, hasLength(1));
      expect(posts.single.id, -1);
    });

    test('normalizes media urls against the server api address', () {
      final posts = buildPosts(_server, [
        _validEntry(
          originalFile: 'images/a.png',
          previewFile: 'https://cdn.example.com/a-thumb.png',
        ),
      ], _mapEntry);

      expect(posts.single.originalFile, 'https://example.com/images/a.png');
      expect(posts.single.previewFile, 'https://cdn.example.com/a-thumb.png');
    });

    test('keeps the percent escapes a media url already carries', () {
      final posts = buildPosts(_server, [
        _validEntry(originalFile: '/images/my%20file.png'),
      ], _mapEntry);

      expect(
        posts.single.originalFile,
        'https://example.com/images/my%20file.png',
      );
    });

    test('falls back to q only when the rating is empty', () {
      final posts = buildPosts(_server, [
        _validEntry(id: 1, originalFile: 'https://cdn.example.com/1.png'),
        _validEntry(id: 2, originalFile: 'https://cdn.example.com/2.png'),
      ], _mapEntry);
      expect(posts.first.rateValue, 'q');

      final explicit = buildPosts(_server, [
        {..._validEntry(id: 3), 'rating': 'e'},
      ], _mapEntry);
      expect(explicit.single.rateValue, 'e');
    });

    test('passes every field through to the post', () {
      final posts = buildPosts(_server, [
        {
          'id': 42,
          'originalFile': 'https://cdn.example.com/42.png',
          'previewFile': 'https://cdn.example.com/42-thumb.png',
          'sampleFile': 'https://cdn.example.com/42-sample.png',
          'width': 800,
          'height': 600,
          'sampleWidth': 400,
          'sampleHeight': 300,
          'previewWidth': 100,
          'previewHeight': 75,
          'rating': 's',
          'source': 'https://source.example.com/42',
          'score': 17,
          'tags': ['a', 'b'],
          'tagsArtist': ['artist'],
          'tagsCharacter': ['character'],
          'tagsCopyright': ['copyright'],
          'tagsGeneral': ['general'],
          'tagsMeta': ['meta'],
        },
      ], _mapEntry);

      final post = posts.single;
      expect(post.id, 42);
      expect(post.originalFile, 'https://cdn.example.com/42.png');
      expect(post.previewFile, 'https://cdn.example.com/42-thumb.png');
      expect(post.sampleFile, 'https://cdn.example.com/42-sample.png');
      expect(post.width, 800);
      expect(post.height, 600);
      expect(post.sampleWidth, 400);
      expect(post.sampleHeight, 300);
      expect(post.previewWidth, 100);
      expect(post.previewHeight, 75);
      expect(post.rateValue, 's');
      expect(post.source, 'https://source.example.com/42');
      expect(post.score, 17);
      expect(post.tags, ['a', 'b']);
      expect(post.tagsArtist, ['artist']);
      expect(post.tagsCharacter, ['character']);
      expect(post.tagsCopyright, ['copyright']);
      expect(post.tagsGeneral, ['general']);
      expect(post.tagsMeta, ['meta']);
      expect(post.serverId, 'Test');
      expect(post.postUrl, 'https://example.com/post/42');
    });

    test('ignores non-map entries', () {
      final posts = buildPosts(_server, [1, 'x', null, <String>[]], _mapEntry);
      expect(posts, isEmpty);
    });
  });
}
