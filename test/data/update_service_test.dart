import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k/data/update/update_service.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('k_update'));
  tearDown(() => tmp.delete(recursive: true));

  final apk = utf8.encode('pretend this is an apk');

  Map<String, Object?> manifest({String? hash}) => {
    'version': '1.2.3',
    'version_code': 10203,
    'apk_url': 'https://example.test/k-1.2.3.apk',
    'sha256': hash ?? sha256.convert(apk).toString(),
    'size_bytes': apk.length,
    'notes': 'New things',
    'min_version_code': 10000,
  };

  UpdateService service(Map<String, Object?> m) => UpdateService(
    manifestUrl: 'https://gist.example.test/k-update.json',
    cacheDir: () async => tmp,
    client: MockClient((req) async {
      if (req.url.path.endsWith('.json')) {
        return http.Response(jsonEncode(m), 200);
      }
      return http.Response.bytes(apk, 200);
    }),
  );

  test('version codes follow major·10000 + minor·100 + patch', () {
    expect(versionCodeOf('1.0.0'), 10000);
    expect(versionCodeOf('1.2.3'), 10203);
    expect(versionCodeOf('2.0.0') > versionCodeOf('1.99.99'), isTrue);
    expect(() => versionCodeOf('1.0'), throwsFormatException);
    expect(() => versionCodeOf('1.100.0'), throwsFormatException);
  });

  test(
    'a newer release is available; below the minimum it is required',
    () async {
      final m = await service(manifest()).fetch();
      expect(m.version, '1.2.3');
      expect(UpdateCheck(m, installedCode: 10203).available, isFalse);
      final old = UpdateCheck(m, installedCode: 10100);
      expect(old.available, isTrue);
      expect(old.required, isFalse);
      expect(UpdateCheck(m, installedCode: 9999).required, isTrue);
    },
  );

  test('download keeps a matching file and rejects a tampered one', () async {
    final ok = service(manifest());
    final file = await ok.download(await ok.fetch());
    expect(await file.readAsBytes(), apk);

    final bad = service(manifest(hash: '0' * 64));
    await expectLater(
      bad.download(await bad.fetch()),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory('${tmp.path}/updates').list().isEmpty, isTrue);
  });
}
