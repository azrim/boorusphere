import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/batch_download_provider.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils/fake_data.dart';

void main() {
  late final Post post;

  setUpAll(() {
    post = getSamplePosts().first.copyWith(
      sampleFile: 'https://example.test/sample.jpg',
      originalFile: 'https://example.test/original.png',
    );
  });

  group('batch source', () {
    test('saves the sample when the setting asks for it', () {
      expect(batchSourceUrlOf(post, DownloadQuality.sample), post.sampleFile);
    });

    test('saves the original when the setting asks for it', () {
      expect(
        batchSourceUrlOf(post, DownloadQuality.original),
        post.originalFile,
      );
    });

    test(
      'saves the original when the setting asks, as a batch has no picker',
      () {
        expect(batchSourceUrlOf(post, DownloadQuality.ask), post.originalFile);
      },
    );

    test('saves the original for an engine without a sample', () {
      final noSample = post.copyWith(sampleFile: '');

      expect(
        batchSourceUrlOf(noSample, DownloadQuality.sample),
        post.originalFile,
      );
    });
  });
}
