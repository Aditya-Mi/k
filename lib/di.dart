import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'core/security/db_key_manager.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final keyManager = DbKeyManager(const FlutterSecureStorage());
  final key = await keyManager.getOrCreateKey();

  getIt
    ..registerSingleton<DbKeyManager>(keyManager)
    ..registerSingleton<AppDatabase>(AppDatabase(openEncryptedDatabase(key)));
}
