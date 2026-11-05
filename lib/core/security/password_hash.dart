import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 passwords. Same wire format as `functions/password_hash.js`:
/// `pbkdf2-sha256$<iterations>$<saltB64url>$<hashB64url>`.
///
/// Production writes go through the admin callable so the server hashes with
/// the full iteration count. This Dart copy verifies hashes (and hashes in
/// unit tests / the offline fallback) and lets the admin UI refuse to display
/// a stored hash as if it were a password.
class PasswordHash {
  static const String prefix = 'pbkdf2-sha256';
  static const int defaultIterations = 210000;
  static const int dkLen = 32;
  static const int saltLen = 16;
  static const int maxIterations = 2000000;

  static bool isHash(String value) => value.startsWith('$prefix\$');

  static String hash(
    String password, {
    int iterations = defaultIterations,
    List<int>? salt,
  }) {
    if (iterations < 1 || iterations > maxIterations) {
      throw ArgumentError('invalid_iterations');
    }
    final saltBytes = salt ??
        List<int>.generate(saltLen, (_) => Random.secure().nextInt(256));
    final dk = pbkdf2Sha256(
      password: utf8.encode(password),
      salt: saltBytes,
      iterations: iterations,
      dkLen: dkLen,
    );
    return '$prefix\$$iterations\$${_b64(saltBytes)}\$${_b64(dk)}';
  }

  /// Hash and plaintext both verify. Plaintext matches are legacy storage.
  static PasswordMatch passwordMatches(String stored, String password) {
    if (stored.isEmpty) return const PasswordMatch(ok: false, legacy: false);
    if (isHash(stored)) {
      return PasswordMatch(ok: verify(stored, password), legacy: false);
    }
    return PasswordMatch(ok: _constEq(stored, password), legacy: true);
  }

  static bool verify(String stored, String password) {
    if (!isHash(stored)) return false;
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != prefix) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1 || iterations > maxIterations) {
      return false;
    }
    final salt = _b64d(parts[2]);
    final expected = _b64d(parts[3]);
    if (salt == null || expected == null || expected.isEmpty) return false;
    final dk = pbkdf2Sha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      dkLen: expected.length,
    );
    return _constEqBytes(dk, expected);
  }

  static Uint8List pbkdf2Sha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int dkLen,
  }) {
    final hmac = Hmac(sha256, password);
    final blockCount = (dkLen / 32).ceil();
    final out = BytesBuilder(copy: false);
    for (var i = 1; i <= blockCount; i++) {
      out.add(_block(hmac, salt, iterations, i));
    }
    final bytes = out.toBytes();
    if (bytes.length == dkLen) return bytes;
    return Uint8List.sublistView(bytes, 0, dkLen);
  }

  static List<int> _block(Hmac hmac, List<int> salt, int iterations, int index) {
    final first = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..setRange(salt.length, salt.length + 4, _int32be(index));
    var u = hmac.convert(first).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  static List<int> _int32be(int i) => [
        (i >> 24) & 0xff,
        (i >> 16) & 0xff,
        (i >> 8) & 0xff,
        i & 0xff,
      ];

  static String _b64(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Uint8List? _b64d(String value) {
    try {
      final pad = value.length % 4 == 0 ? '' : '=' * (4 - value.length % 4);
      return Uint8List.fromList(base64Url.decode('$value$pad'));
    } catch (_) {
      return null;
    }
  }

  static bool _constEq(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    return _constEqBytes(ab, bb);
  }

  static bool _constEqBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class PasswordMatch {
  final bool ok;
  final bool legacy;
  const PasswordMatch({required this.ok, required this.legacy});
}
