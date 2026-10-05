import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'app/notifications.dart';
import 'core/security/db_key_manager.dart';
import 'data/backup/backup_service.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/db/seed/seeder.dart';
import 'data/email/email_sync.dart';
import 'data/emis/emi_service.dart';
import 'data/email/google_auth.dart';
import 'data/ingest/ingestion_service.dart';
import 'data/ingest/sms_sync.dart';
import 'data/ingest/transfer_linker.dart';
import 'data/repositories/bank_repository.dart';
import 'data/repositories/ledger_repository.dart';
import 'data/review/learned_formats.dart';
import 'data/review/review_service.dart';
import 'data/repositories/settings_repository.dart';
import 'data/subscriptions/subscription_service.dart';
import 'data/update/update_service.dart';
import 'platform/sms_bridge.dart';
import 'platform/update_bridge.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  const secure = FlutterSecureStorage();
  final keyManager = DbKeyManager(secure);
  final key = await keyManager.getOrCreateKey();
  final db = AppDatabase(openEncryptedDatabase(key));
  final settings = SettingsRepository(db);
  final ingestion = IngestionService(db);
  final bridge = SmsBridge();
  final google = GoogleAuth();
  final ledger = LedgerRepository(db, onRulesChanged: ingestion.invalidate);
  final notifications = KNotifications(db, ledger, settings);
  late final SubscriptionService subscriptions;
  late final EmiService emis;
  Future<void> syncReminders() async => notifications.syncReminders(
    (await subscriptions.watch().first).active,
    await emis.watch().first,
  );
  emis = EmiService(db, settings, onChanged: syncReminders);
  subscriptions = SubscriptionService(
    db,
    ledger,
    settings,
    onChanged: syncReminders,
    alsoRefresh: () => emis.refresh(),
  );

  getIt
    ..registerSingleton<DbKeyManager>(keyManager)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<SettingsRepository>(settings)
    ..registerSingleton<LedgerRepository>(ledger)
    ..registerLazySingleton<BankRepository>(
      () => BankRepository(db, onRulesChanged: ingestion.invalidate),
    )
    ..registerSingleton<KNotifications>(notifications)
    ..registerSingleton<SubscriptionService>(subscriptions)
    ..registerSingleton<EmiService>(emis)
    ..registerSingleton<IngestionService>(ingestion)
    ..registerSingleton<TransferLinker>(TransferLinker(db))
    ..registerSingleton<SmsBridge>(bridge)
    ..registerLazySingleton<UpdateBridge>(UpdateBridge.new)
    // Set by the release workflow (--dart-define); empty in local builds.
    ..registerLazySingleton<UpdateService>(
      () => UpdateService(
        manifestUrl: const String.fromEnvironment('UPDATE_MANIFEST_URL'),
      ),
    )
    ..registerLazySingleton<ReviewService>(
      () => ReviewService(
        db,
        ingestion,
        getIt<LedgerRepository>(),
        getIt<BankRepository>(),
      ),
    )
    ..registerLazySingleton<LearnedFormats>(() => LearnedFormats(db, ingestion))
    ..registerSingleton<GoogleAuth>(google)
    ..registerSingleton<EmailSync>(
      EmailSync(
        db,
        ingestion,
        settings,
        secure,
        google: google,
        onLive: notifications.notifyNew,
      ),
    )
    ..registerSingleton<SmsSync>(
      SmsSync(bridge, ingestion, settings, onLive: notifications.notifyNew),
    )
    ..registerSingleton<BackupService>(
      BackupService(
        db,
        settings,
        secure,
        google,
        bridge,
        onRestored: () async {
          // A backup from an older k lacks newer seed rows.
          await Seeder(db).seedAll();
          ingestion.invalidate();
          await subscriptions.refresh();
          await ingestion.reprocessReview();
        },
      ),
    );
}
