import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Raised when an archive cannot be decrypted.
///
/// A wrong passphrase and a damaged file fail the same GCM tag check, so the
/// message does not say which of the two happened.
class BackupCipherException implements Exception {
  const BackupCipherException();

  @override
  String toString() => 'The backup could not be opened with that passphrase';
}

/// Seals a backup archive with AES-256-GCM under a passphrase.
///
/// The whole ZIP is encrypted as a single blob, so the archive layout is not
/// exposed. The key is derived with PBKDF2-HMAC-SHA256 from the passphrase and
/// a random salt; the salt and the nonce travel in the file header, the
/// passphrase itself is never written anywhere.
class BackupCipher {
  BackupCipher._();

  /// Marks a file as one of ours, so restore detects an encrypted archive by
  /// content instead of trusting its extension.
  static final Uint8List _magic = Uint8List.fromList(utf8.encode('BSPHENC1'));

  static const _saltLength = 16;
  static const _nonceLength = 12;

  /// GCM tag length in bytes; AEADParameters takes it in bits.
  static const _tagLength = 16;
  static const _keyLength = 32;
  static const _iterations = 120000;

  /// magic + salt + nonce; the ciphertext and its tag follow it.
  static const _headerLength = 8 + _saltLength + _nonceLength;

  /// Smallest file this format can produce: the header plus the GCM tag.
  static const _minLength = _headerLength + _tagLength;

  /// Whether [data] starts with the envelope header of an encrypted backup.
  static bool isEncrypted(List<int> data) {
    if (data.length < _minLength) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  /// Encrypts [plaintext] and returns the whole envelope.
  static Uint8List encrypt(Uint8List plaintext, String passphrase) {
    final random = Random.secure();
    final salt = _randomBytes(random, _saltLength);
    final nonce = _randomBytes(random, _nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_deriveKey(passphrase, salt)),
          _tagLength * 8,
          nonce,
          Uint8List(0),
        ),
      );
    // The tag is appended to the ciphertext, which is what makes a truncated
    // or edited file fail on the way back in.
    final sealed = cipher.process(plaintext);

    final output = Uint8List(_headerLength + sealed.length);
    output
      ..setRange(0, _magic.length, _magic)
      ..setRange(_magic.length, _magic.length + _saltLength, salt)
      ..setRange(_magic.length + _saltLength, _headerLength, nonce)
      ..setRange(_headerLength, output.length, sealed);
    return output;
  }

  /// Decrypts [data], which must be a complete envelope.
  ///
  /// Throws [BackupCipherException] when the header is missing, the file is
  /// truncated, or the passphrase is wrong. No plaintext is returned unless
  /// the whole archive authenticated.
  static Uint8List decrypt(Uint8List data, String passphrase) {
    if (!isEncrypted(data)) throw const BackupCipherException();

    final salt = data.sublist(_magic.length, _magic.length + _saltLength);
    final nonce = data.sublist(_magic.length + _saltLength, _headerLength);
    final sealed = Uint8List.sublistView(data, _headerLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(_deriveKey(passphrase, salt)),
          _tagLength * 8,
          nonce,
          Uint8List(0),
        ),
      );
    try {
      return cipher.process(sealed);
    } on Object {
      // The tag check is the only failure this format can report, and it
      // covers both a wrong passphrase and a corrupted file.
      throw const BackupCipherException();
    }
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _randomBytes(Random random, int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
