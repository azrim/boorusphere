import 'package:mime/mime.dart';
import 'package:path/path.dart';

/// [Uri.decodeComponent] that falls back to the raw value when the escape is
/// malformed, so a file name served without proper encoding cannot abort the
/// caller before it starts.
String decodeComponentSafely(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

extension StringExt on String {
  String get mimeType {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  String get fileName {
    return basename(toUri().path);
  }

  String get fileNameNoExt {
    return withoutExtension(fileName);
  }

  String get fileExt {
    return extension(toUri().path).replaceFirst('.', '');
  }

  Uri toUri() {
    return Uri.parse(this);
  }

  List<String> toWordList() {
    return replaceAll(
      RegExp('\\s+'),
      ' ',
    ).trim().split(' ').where((it) => it.isNotEmpty).toList();
  }
}
