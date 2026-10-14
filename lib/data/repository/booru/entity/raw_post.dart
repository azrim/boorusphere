/// A parser's raw, un-normalized view of a single post entry.
///
/// Search parsers map each engine-specific map into a [RawPost], handing over
/// the final values (including engine-decoded tags) while leaving URL
/// normalization, the file/content guard, de-duplication and the rating
/// fallback to the shared post pipeline (`buildPosts`).
class RawPost {
  const RawPost({
    required this.id,
    required this.originalFile,
    required this.previewFile,
    this.sampleFile = '',
    this.width = -1,
    this.height = -1,
    this.sampleWidth = -1,
    this.sampleHeight = -1,
    this.previewWidth = -1,
    this.previewHeight = -1,
    this.rating = '',
    this.source = '',
    this.score = 0,
    this.tags = const [],
    this.tagsArtist = const [],
    this.tagsCharacter = const [],
    this.tagsCopyright = const [],
    this.tagsGeneral = const [],
    this.tagsMeta = const [],
  });

  final int id;
  final String originalFile;
  final String previewFile;
  final String sampleFile;
  final int width;
  final int height;
  final int sampleWidth;
  final int sampleHeight;
  final int previewWidth;
  final int previewHeight;
  final String rating;
  final String source;
  final int score;
  final List<String> tags;
  final List<String> tagsArtist;
  final List<String> tagsCharacter;
  final List<String> tagsCopyright;
  final List<String> tagsGeneral;
  final List<String> tagsMeta;
}
