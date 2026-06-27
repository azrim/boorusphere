import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Content.asContent', () {
    test('detects video MIME types', () {
      expect('test.mp4'.asContent().isVideo, isTrue);
      expect('test.webm'.asContent().isVideo, isTrue);
    });

    test('detects gif by extension', () {
      expect('test.gif'.asContent().isGif, isTrue);
    });

    test('detects photo for images', () {
      expect('test.jpg'.asContent().isPhoto, isTrue);
      expect('test.png'.asContent().isPhoto, isTrue);
      expect('test.webp'.asContent().isPhoto, isTrue);
    });

    test('unsupported for unknown extension', () {
      expect('test.xyz'.asContent().isUnsupported, isTrue);
    });

    test('stores url on content', () {
      final content = 'photo.jpg'.asContent();
      expect(content.url, 'photo.jpg');
    });
  });

  group('PixelSize', () {
    test('hasPixels returns true for positive dimensions', () {
      const size = PixelSize(width: 100, height: 200);
      expect(size.hasPixels, isTrue);
    });

    test('hasPixels returns false for default', () {
      const size = PixelSize();
      expect(size.hasPixels, isFalse);
    });

    test('aspectRatio computes correctly', () {
      const size = PixelSize(width: 200, height: 100);
      expect(size.aspectRatio, 2.0);
    });

    test('aspectRatio handles zero height', () {
      const size = PixelSize(width: 200, height: 0);
      expect(
        size.aspectRatio.isInfinite || size.aspectRatio.isNaN,
        isTrue,
      );
    });

    test('toString with pixels', () {
      const size = PixelSize(width: 1920, height: 1080);
      expect(size.toString(), '1920x1080');
    });

    test('toString without pixels', () {
      const size = PixelSize();
      expect(size.toString(), 'unknown size');
    });
  });
}
