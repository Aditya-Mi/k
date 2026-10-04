import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'app/notifications.dart';
import 'core/security/db_key_manager.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/email/email_sync.dart';
import 'data/ingest/ingestion_service.dart';
import 'data/ingest/sms_sync.dart';
import 'data/ingest/transfer_linker.dart';
import 'data/repositories/ledger_repository.dart';
import 'data/review/learned_formats.dart';
import 'data/review/review_service.dart';
import 'data/repositories/settings_repository.dart';
import 'data/subscriptions/subscription_service.dart';
import 'platform/sms_bridge.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  const secure = FlutterSecureStorage();
  final keyManager = DbKeyManager(secure);
  final key = await keyManager.getOrCreateKey();
  final db = AppDatabase(openEncryptedDatabase(key));
  final settings = SettingsRepository(db);
  final ingestion = IngestionService(db);
  final bridge = SmsBridge();
  final ledger = LedgerRepository(db, onRulesChanged: ingestion.invalidate);
  final notifications = KNotifications(db, ledger, settings);
  late final SubscriptionService subscriptions;
  subscriptions = SubscriptionService(
    db,
    ledger,
    settings,
    onChanged: () async =>
        notifications.syncReminders((await subscriptions.watch().first).active),
  );

  getIt
    ..registerSingleton<DbKeyManager>(keyManager)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<SettingsRepository>(settings)
    ..registerSingleton<LedgerRepository>(ledger)
    ..registerSingleton<KNotifications>(notifications)
    ..registerSingleton<SubscriptionService>(subscriptions)
    ..registerSingleton<IngestionService>(ingestion)
    ..registerSingleton<TransferLinker>(TransferLinker(db))
    ..registerSingleton<SmsBridge>(bridge)
    ..registerLazySingleton<ReviewService>(
      () => ReviewService(db, ingestion, getIt<LedgerRepository>()),
    )
    ..registerLazySingleton<LearnedFormats>(() => LearnedFormats(db, ingestion))
    ..registerSingleton<EmailSync>(
      EmailSync(
        db,
        ingestion,
        settings,
        secure,
        onLive: notifications.notifyNew,
      ),
    )
    ..registerSingleton<SmsSync>(
      SmsSync(bridge, ingestion, settings, onLive: notifications.notifyNew),
    );
}
