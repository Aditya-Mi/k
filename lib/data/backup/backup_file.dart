import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The `.kbackup` file: a small JSON envelope around the encrypted snapshot.
///
/// ```
/// {"header": "<json: k, v, meta, kdf>", "nonce": b64, "data": b64}
/// ```
/// `data` is AES-256-GCM (ciphertext + 16-byte tag) over the gzipped
/// snapshot JSON; the header string is the associated data, so its counts
/// and KDF settings can't be altered. The key comes from the owner's
/// passphrase via Argon2id; the salt is in the header.
class BackupFile {
  BackupFile._(this.header, this.headerText, this.nonce, this.data);

  static const extension = 'kbackup';
  static const _format = 'k-backup';
  static const _version = 1;

  final BackupHeader header;
  final String headerText;
  final Uint8List nonce;
  final Uint8List data;

  /// Throws [FormatException] for anything that isn't a k backup.
  factory BackupFile.parse(List<int> bytes) {
    try {
      final outer = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final headerText = outer['header'] as String;
      final h = jsonDecode(headerText) as Map<String, dynamic>;
      if (h['k'] != _format) throw const FormatException('not a k backup');
      if ((h['v'] as int) > _version) {
        throw const FormatException('made by a newer k; update k first');
      }
      return BackupFile._(
        BackupHeader.fromJson(h),
        headerText,
        base64Decode(outer['nonce'] as String),
        base64Decode(outer['data'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('not a k backup');
    }
  }

  /// Encrypts [snapshot] under [key] (derived with [kdf]).
  static Future<Uint8List> seal({
    required Map<String, dynamic> snapshot,
    required BackupMeta meta,
    required KdfParams kdf,
    required List<int> key,
  }) async {
    final headerText = jsonEncode({
      'k': _format,
      'v': _version,
      'meta': meta.toJson(),
      'kdf': kdf.toJson(),
    });
    final plain = gzip.encode(utf8.encode(jsonEncode(snapshot)));
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(key),
      aad: utf8.encode(headerText),
    );
    return utf8.encode(
      jsonEncode({
        'header': headerText,
        'nonce': base64Encode(box.nonce),
        'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
      }),
    );
  }

  /// The snapshot, or [BackupKeyException] when [key] doesn't open it.
  Future<Map<String, dynamic>> open(List<int> key) async {
    if (data.length < 16) throw const FormatException('backup is damaged');
    final cut = data.length - 16;
    final List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          data.sublist(0, cut),
          nonce: nonce,
          mac: Mac(data.sublist(cut)),
        ),
        secretKey: SecretKey(key),
        aad: utf8.encode(headerText),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupKeyException();
    }
    return jsonDecode(utf8.decode(gzip.decode(plain))) as Map<String, dynamic>;
  }
}

/// Wrong passphrase (or a tampered file — GCM can't tell them apart).
class BackupKeyException implements Exception {
  const BackupKeyException();

  @override
  String toString() => "That passphrase doesn't open this backup";
}

class BackupHeader {
  const BackupHeader(this.meta, this.kdf);

  factory BackupHeader.fromJson(Map<String, dynamic> j) => BackupHeader(
    BackupMeta.fromJson(j['meta'] as Map<String, dynamic>),
    KdfParams.fromJson(j['kdf'] as Map<String, dynamic>),
  );

  final BackupMeta meta;
  final KdfParams kdf;
}

/// What the restore screen shows before the passphrase (design 06g).
class BackupMeta {
  const BackupMeta({
    required this.createdAt,
    required this.schemaVersion,
    required this.payments,
    required this.accounts,
    required this.subscriptions,
    required this.formats,
  });

  factory BackupMeta.fromJson(Map<String, dynamic> j) => BackupMeta(
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    schemaVersion: j['schema'] as int,
    payments: j['payments'] as int? ?? 0,
    accounts: j['accounts'] as int? ?? 0,
    subscriptions: j['subscriptions'] as int? ?? 0,
    formats: j['formats'] as int? ?? 0,
  );

  final DateTime createdAt;
  final int schemaVersion;
  final int payments;
  final int accounts;
  final int subscriptions;
  final int formats;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'schema': schemaVersion,
    'payments': payments,
    'accounts': accounts,
    'subscriptions': subscriptions,
    'formats': formats,
  };
}

/// Argon2id settings + salt. Defaults follow OWASP's 19 MiB / t=2 / p=1.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memoryKib = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  factory KdfParams.fresh() {
    final r = Random.secure();
    return KdfParams(salt: [for (var i = 0; i < 16; i++) r.nextInt(256)]);
  }

  factory KdfParams.fromJson(Map<String, dynamic> j) {
    if (j['alg'] != 'argon2id') throw const FormatException('unknown key type');
    return KdfParams(
      salt: base64Decode(j['salt'] as String),
      memoryKib: j['m'] as int,
      iterations: j['t'] as int,
      parallelism: j['p'] as int,
    );
  }

  final List<int> salt;
  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'alg': 'argon2id',
    'salt': base64Encode(salt),
    'm': memoryKib,
    't': iterations,
    'p': parallelism,
  };

  bool sameAs(KdfParams o) =>
      base64Encode(salt) == base64Encode(o.salt) &&
      memoryKib == o.memoryKib &&
      iterations == o.iterations &&
      parallelism == o.parallelism;

  /// Slow on purpose (about a second on a phone), so off the UI isolate.
  Future<Uint8List> derive(String passphrase) {
    final p = toJson();
    return Isolate.run(() async {
      final k = KdfParams.fromJson(p);
      final key = await Argon2id(
        parallelism: k.parallelism,
        memory: k.memoryKib,
        iterations: k.iterations,
        hashLength: 32,
      ).deriveKeyFromPassword(password: passphrase, nonce: k.salt);
      return Uint8List.fromList(await key.extractBytes());
    });
  }
}
