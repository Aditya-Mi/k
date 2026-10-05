import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The release the update gist points at. Written by the release workflow
/// (`.github/workflows/release.yml`); k only reads it.
class UpdateManifest extends Equatable {
  const UpdateManifest({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    this.notes = '',
    this.minVersionCode = 0,
  });

  factory UpdateManifest.fromJson(Map<String, Object?> j) => UpdateManifest(
    version: j['version']! as String,
    versionCode: (j['version_code']! as num).toInt(),
    apkUrl: j['apk_url']! as String,
    sha256: (j['sha256']! as String).toLowerCase(),
    sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
    notes: j['notes'] as String? ?? '',
    minVersionCode: (j['min_version_code'] as num?)?.toInt() ?? 0,
  );

  final String version;

  /// Build number: 1 for the first release, +1 per release.
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;

  /// Installs below this must update (no "Later").
  final int minVersionCode;

  @override
  List<Object?> get props => [version, versionCode, apkUrl, sha256];
}

class UpdateCheck {
  const UpdateCheck(this.manifest, {required this.installedCode});

  final UpdateManifest manifest;
  final int installedCode;

  bool get available => manifest.versionCode > installedCode;
  bool get required => installedCode < manifest.minVersionCode;
}

/// Reads the update gist and downloads a release APK, checking it against
/// the SHA-256 the workflow published. Sends nothing about the owner: a
/// plain GET of a public file.
class UpdateService {
  UpdateService({
    required this.manifestUrl,
    http.Client? client,
    Future<Directory> Function()? cacheDir,
  }) : _client = client ?? http.Client(),
       _cacheDir = cacheDir ?? getTemporaryDirectory;

  /// Raw gist URL; empty in local builds (no update checks).
  final String manifestUrl;
  final http.Client _client;
  final Future<Directory> Function() _cacheDir;

  bool get enabled => manifestUrl.isNotEmpty;

  Future<UpdateManifest> fetch() async {
    // Gist raw files sit behind a CDN; a query string skips its cache.
    final url = Uri.parse(manifestUrl).replace(
      queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    final res = await _client.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw HttpException('update check failed (${res.statusCode})');
    }
    return UpdateManifest.fromJson(
      jsonDecode(res.body) as Map<String, Object?>,
    );
  }

  /// Downloads into the cache (where the installer's FileProvider looks) and
  /// verifies the hash. [onProgress] gets 0–1, or null while size is unknown.
  Future<File> download(
    UpdateManifest m, {
    void Function(double? progress)? onProgress,
  }) async {
    final dir = Directory('${(await _cacheDir()).path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/k-${m.version}.apk');

    final res = await _client.send(http.Request('GET', Uri.parse(m.apkUrl)));
    if (res.statusCode != 200) {
      throw HttpException('download failed (${res.statusCode})');
    }
    final total = res.contentLength ?? m.sizeBytes;
    final sink = file.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : null);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    if (digest.value.toString() != m.sha256) {
      await file.delete();
      throw const FileSystemException('the download did not match the release');
    }
    return file;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
