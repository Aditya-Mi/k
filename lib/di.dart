import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'core/security/db_key_manager.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/ingest/ingestion_service.dart';
import 'data/ingest/sms_sync.dart';
import 'data/ingest/transfer_linker.dart';
import 'data/repositories/ledger_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'platform/sms_bridge.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final keyManager = DbKeyManager(const FlutterSecureStorage());
  final key = await keyManager.getOrCreateKey();
  final db = AppDatabase(openEncryptedDatabase(key));
  final settings = SettingsRepository(db);
  final ingestion = IngestionService(db);
  final bridge = SmsBridge();

  getIt
    ..registerSingleton<DbKeyManager>(keyManager)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<SettingsRepository>(settings)
    ..registerSingleton<LedgerRepository>(LedgerRepository(db))
    ..registerSingleton<IngestionService>(ingestion)
    ..registerSingleton<TransferLinker>(TransferLinker(db))
    ..registerSingleton<SmsBridge>(bridge)
    ..registerSingleton<SmsSync>(SmsSync(bridge, ingestion, settings));
}
