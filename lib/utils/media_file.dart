import 'dart:io';

import 'package:path/path.dart' as p;

/// Bytes read from the head of a file to identify its container: enough for
/// the JPEG/PNG/GIF signatures, the `RIFF....WEBP` header and the
/// `....ftyp` box of an ISO base media file.
const _headLength = 12;

const _jpegSignature = <int>[0xFF, 0xD8, 0xFF];
const _pngSignature = <int>[0x89, 0x50, 0x4E, 0x47];
const _gifSignature = <int>[0x47, 0x49, 0x46];
const _riffSignature = <int>[0x52, 0x49, 0x46, 0x46];
const _webpSignature = <int>[0x57, 0x45, 0x42, 0x50];
const _mp4Signature = <int>[0x66, 0x74, 0x79, 0x70];

/// Extensions this app hands out; a file carrying one of them is expected to
/// start with a matching signature.
const _mediaExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.mp4',
  '.m4v',
  '.mov',
};

/// Whether [file] is a non-empty file whose head matches a media container
/// this app writes.
///
/// The check stays lenient on purpose: bytes of a known container pass
/// whatever the extension says, and an extension that is not a media one
/// passes unless the head is plainly markup. What it rejects is the empty file
/// and the HTML page a hotlink-protected booru sends in place of the image.
bool isMediaFile(File file) {
  try {
    if (!file.existsSync() || file.lengthSync() == 0) return false;

    final head = _readHead(file);
    if (head.isEmpty) return false;

    if (_hasSignature(head, _jpegSignature) ||
        _hasSignature(head, _pngSignature) ||
        _hasSignature(head, _gifSignature) ||
        (_hasSignature(head, _riffSignature) &&
            _hasSignature(head, _webpSignature, offset: 8)) ||
        _hasSignature(head, _mp4Signature, offset: 4)) {
      return true;
    }

    if (_mediaExtensions.contains(p.extension(file.path).toLowerCase())) {
      return false;
    }
    return !_looksLikeMarkup(head);
  } catch (_) {
    // An unreadable file is not a file this app can hand to the gallery or
    // the viewer, so it fails the check instead of aborting the caller.
    return false;
  }
}

List<int> _readHead(File file) {
  final handle = file.openSync();
  try {
    return handle.readSync(_headLength);
  } finally {
    handle.closeSync();
  }
}

bool _hasSignature(List<int> head, List<int> signature, {int offset = 0}) {
  if (head.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (head[offset + i] != signature[i]) return false;
  }
  return true;
}

bool _looksLikeMarkup(List<int> head) {
  for (final byte in head) {
    final isWhitespace =
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;
    if (isWhitespace) continue;
    // `<`, `{` and `[` open the HTML or JSON payloads a server returns
    // instead of the media it was asked for.
    return byte == 0x3C || byte == 0x7B || byte == 0x5B;
  }
  return true;
}
