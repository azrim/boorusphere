import 'package:boorusphere/utils/extensions/string.dart';

enum PostType {
  video,
  photo,
  gif,
  unsupported,
}

class Content {
  const Content({
    required this.type,
    required this.url,
  });

  final PostType type;
  final String url;

  bool get isPhoto => type == PostType.photo;
  bool get isVideo => type == PostType.video;
  bool get isGif => type == PostType.gif;
  bool get isUnsupported => type == PostType.unsupported;
}

extension ContentExt on String {
  Content asContent() {
    PostType type;
    final mime = mimeType;
    final ext = fileExt.toLowerCase();

    if (mime.startsWith('video')) {
      type = PostType.video;
    } else if (mime == 'image/gif' || ext == 'gif') {
      // Check for GIF by MIME type or extension
      type = PostType.gif;
    } else if (mime.startsWith('image')) {
      type = PostType.photo;
    } else {
      type = PostType.unsupported;
    }
    return Content(type: type, url: this);
  }
}
