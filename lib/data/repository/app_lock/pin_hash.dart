import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Iterations used for a new PIN. The count travels with the record, so a
/// future build can raise it without breaking an existing PIN.
///
/// The verifier guards a four to eight digit code, so the guess space is a
/// few thousand at most: the KDF is a pace-setter against a brute force of
/// that space, not a stand-in for a password's entropy. 32k runs in a few
/// hundred milliseconds on a low-end phone, long enough to make a million
/// guesses take a month while a typed entry still opens at a tap.
const int defaultPinIterations = 32000;

const int _saltLength = 16;
const int _keyLength = 32;

/// A salted PBKDF2-HMAC-SHA256 verifier for an app PIN.
///
/// The PIN itself is never stored. The salt makes the same PIN produce a
/// different verifier on every device, and the iteration count is kept so it
/// can be raised later without invalidating existing records.
class PinHash {
  const PinHash({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;

  static PinHash create(
    String pin, {
    int iterations = defaultPinIterations,
    Random? random,
  }) {
    final salt = Uint8List(_saltLength);
    final source = random ?? Random.secure();
    for (var i = 0; i < salt.length; i++) {
      salt[i] = source.nextInt(256);
    }

    return PinHash(
      salt: salt,
      hash: derivePinHash(pin, salt, iterations),
      iterations: iterations,
    );
  }

  bool matches(String pin) {
    return constantTimeEquals(hash, derivePinHash(pin, salt, iterations));
  }

  Map<String, Object> toJson() {
    return {
      'iterations': iterations,
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
    };
  }

  /// Reads a stored verifier, or null when the value cannot be a verifier.
  ///
  /// A damaged record is treated as no PIN by the caller, never as a record
  /// that could throw during the start of the app.
  static PinHash? tryParse(Object? value) {
    if (value is! Map) return null;

    final iterations = value['iterations'];
    final salt = value['salt'];
    final hash = value['hash'];
    if (iterations is! int || iterations < 1) return null;
    if (salt is! String || hash is! String) return null;

    try {
      final saltBytes = base64Decode(salt);
      final hashBytes = base64Decode(hash);
      if (saltBytes.isEmpty || hashBytes.isEmpty) return null;
      return PinHash(
        salt: Uint8List.fromList(saltBytes),
        hash: Uint8List.fromList(hashBytes),
        iterations: iterations,
      );
    } on FormatException {
      return null;
    }
  }
}

Uint8List derivePinHash(String pin, List<int> salt, int iterations) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, _keyLength));
  return derivator.process(Uint8List.fromList(utf8.encode(pin)));
}

/// Compares two byte lists without exiting at the first difference.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;

  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
