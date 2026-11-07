import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/utils/entity/content.dart';
import 'package:boorusphere/presentation/utils/entity/pixel_size.dart';

extension PostExt on Post {
  bool get hasCategorizedTags => [
    ...tagsArtist,
    ...tagsCharacter,
    ...tagsCopyright,
    ...tagsGeneral,
    ...tagsMeta,
  ].isNotEmpty;

  Set<String> get allTags => {
    ...tagsArtist,
    ...tagsCharacter,
    ...tagsCopyright,
    ...tagsGeneral,
    ...tagsMeta,
    ...tags,
  };

  String get describeTags => allTags.join(' ');

  double get aspectRatio {
    final ratio = prescreensize.hasPixels
        ? prescreensize.aspectRatio
        : sampleSize.hasPixels
        ? sampleSize.aspectRatio
        : originalSize.aspectRatio;
    // Unknown dimensions are a normal state in a booru client: a parser may
    // report 0/0 (e621 fills a missing file block with zeros) or a partial
    // size. NaN, Infinity or a negative ratio would throw in the card's
    // decode math and trip AspectRatio's positivity assert, so the card reads
    // it as a square instead of failing to build.
    return ratio.isFinite && ratio > 0 ? ratio : 1.0;
  }

  PixelSize get originalSize => PixelSize(width: width, height: height);

  PixelSize get sampleSize =>
      PixelSize(width: sampleWidth, height: sampleHeight);

  PixelSize get prescreensize =>
      PixelSize(width: previewWidth, height: previewHeight);

  BooruRating get rating => BooruRating.parse(rateValue);

  Content get content {
    final sample = sampleFile.asContent();
    final original = originalFile.asContent();
    if (sample.isPhoto && (original.isVideo || original.isGif) ||
        sample.isUnsupported) {
      return original;
    }

    return sample;
  }

  String get viewId {
    return '$id-$serverId';
  }
}
