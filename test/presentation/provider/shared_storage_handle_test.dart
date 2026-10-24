import 'dart:io';

import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late SharedStorageHandle storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shared_storage_handle');
    storage = SharedStorageHandle(downloadPath: tempDir.path);
    Directory(storage.path).createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, List<int> bytes) {
    final file = File(p.join(storage.path, name));
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('SharedStorageHandle.isValidMedia', () {
    test('rejects an empty file', () {
      writeFile('empty.jpg', const []);

      expect(storage.isValidMedia('empty.jpg'), isFalse);
    });

    test('rejects a file that does not exist', () {
      expect(storage.isValidMedia('missing.jpg'), isFalse);
    });

    test('accepts a file with the jpeg signature', () {
      writeFile('photo.jpg', const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      expect(storage.isValidMedia('photo.jpg'), isTrue);
    });

    test('accepts a signature even when the extension disagrees', () {
      writeFile('download.jpg', const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

      expect(storage.isValidMedia('download.jpg'), isTrue);
    });

    test('rejects an HTML page served for a media extension', () {
      writeFile(
        'page.jpg',
        '<!DOCTYPE html><html><body>blocked</body>'.codeUnits,
      );

      expect(storage.isValidMedia('page.jpg'), isFalse);
    });

    test('rejects markup leading with whitespace', () {
      writeFile('spaced.jpg', '\n  <html></html>'.codeUnits);

      expect(storage.isValidMedia('spaced.jpg'), isFalse);
    });

    test('accepts unknown extensions unless the head is markup', () {
      writeFile('blob.dat', 'PLAINBYTES'.codeUnits);

      expect(storage.isValidMedia('blob.dat'), isTrue);
    });

    test('accepts an absolute path outside the download folder', () {
      final file = File(p.join(tempDir.path, 'temp.m4v'))
        ..writeAsBytesSync(const [
          0x00,
          0x00,
          0x00,
          0x18,
          0x66,
          0x74,
          0x79,
          0x70,
        ]);

      expect(storage.isValidMedia(file.path), isTrue);
    });
  });
}
