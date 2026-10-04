import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One backup file on Drive.
class DriveBackup {
  const DriveBackup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.size,
    required this.payments,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int size;

  /// From the file's appProperties, so the list needs no download.
  final int? payments;
}

/// Drive REST v3 with the `drive.file` scope: k sees only files it made.
/// Backups live in a "k backups" folder in the owner's My Drive.
class DriveClient {
  DriveClient({
    required this.accessToken,
    required this.dropToken,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final Future<String?> Function() accessToken;
  final Future<void> Function(String token) dropToken;
  final http.Client _http;

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _folderName = 'k backups';
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// The backups folder, made on first use.
  Future<String> folder() async {
    final found = await _json(
      'GET',
      '$_api/files',
      query: {
        'q':
            "name = '$_folderName' and mimeType = '$_folderMime' and trashed = false",
        'fields': 'files(id)',
        'spaces': 'drive',
      },
    );
    final files = found['files'] as List;
    if (files.isNotEmpty) return (files.first as Map)['id'] as String;
    final made = await _json(
      'POST',
      '$_api/files',
      body: jsonEncode({'name': _folderName, 'mimeType': _folderMime}),
      query: {'fields': 'id'},
    );
    return made['id'] as String;
  }

  /// Newest first.
  Future<List<DriveBackup>> list(String folderId) async {
    final r = await _json(
      'GET',
      '$_api/files',
      query: {
        'q': "'$folderId' in parents and trashed = false",
        'orderBy': 'createdTime desc',
        'pageSize': '100',
        'fields': 'files(id,name,size,createdTime,appProperties)',
      },
    );
    return [
      for (final f in (r['files'] as List).cast<Map<String, dynamic>>())
        DriveBackup(
          id: f['id'] as String,
          name: f['name'] as String,
          createdAt: DateTime.parse(f['createdTime'] as String).toLocal(),
          size: int.tryParse('${f['size']}') ?? 0,
          payments: int.tryParse(
            '${(f['appProperties'] as Map?)?['payments']}',
          ),
        ),
    ];
  }

  /// Resumable upload (works for any size).
  Future<void> upload({
    required String folderId,
    required String name,
    required Uint8List bytes,
    Map<String, String> properties = const {},
  }) async {
    final start = await _send(
      'POST',
      Uri.parse(
        '$_upload/files',
      ).replace(queryParameters: {'uploadType': 'resumable', 'fields': 'id'}),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: jsonEncode({
        'name': name,
        'parents': [folderId],
        'appProperties': properties,
      }),
    );
    final session = start.headers['location'];
    if (session == null) throw http.ClientException('Drive: no upload session');
    await _send(
      'PUT',
      Uri.parse(session),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
  }

  Future<Uint8List> download(String fileId) async => (await _send(
    'GET',
    Uri.parse('$_api/files/$fileId').replace(queryParameters: {'alt': 'media'}),
  )).bodyBytes;

  Future<void> delete(String fileId) =>
      _send('DELETE', Uri.parse('$_api/files/$fileId'));

  Future<Map<String, dynamic>> _json(
    String method,
    String url, {
    Map<String, String>? query,
    String? body,
  }) async {
    final res = await _send(
      method,
      Uri.parse(url).replace(queryParameters: query),
      headers: body == null ? null : {'Content-Type': 'application/json'},
      body: body,
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken();
      if (token == null) throw const DriveAuthException();
      final req = http.Request(method, uri)
        ..headers.addAll({'Authorization': 'Bearer $token', ...?headers});
      if (body is String) req.body = body;
      if (body is List<int>) req.bodyBytes = body;
      final res = await http.Response.fromStream(await _http.send(req));
      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      if (res.statusCode == 401 && attempt == 0) {
        await dropToken(token);
        continue;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const DriveAuthException();
      }
      throw http.ClientException('Drive ${res.statusCode}', uri);
    }
  }
}

class DriveAuthException implements Exception {
  const DriveAuthException();

  @override
  String toString() => 'Sign in with Google again';
}
