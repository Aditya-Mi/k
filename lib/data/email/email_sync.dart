import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:txn_parser/txn_parser.dart' show Channel;

import '../backup/backup_service.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../ingest/ingestion_service.dart';
import '../repositories/settings_repository.dart';
import 'email_source.dart';
import 'google_auth.dart';
import 'imap_source.dart';

/// An inbox as Settings shows it.
class EmailAccountView extends Equatable {
  const EmailAccountView(this.row, {this.error});

  final EmailAccount row;

  /// Last sync's failure, shown until a sync succeeds.
  final String? error;

  @override
  List<Object?> get props => [row, error];
}

/// Builds a source for an account (tests swap in fakes).
typedef SourceFactory = Future<EmailSource?> Function(
  EmailAccount account,
  String? secret,
);

/// Pulls bank alert mail into the ledger, hourly in the background and on
/// demand. Only mail from bank email senders is fetched; each mail goes
/// through the same ingestion as SMS, so SMS + email of one payment merge.
/// Secrets (app passwords) live in secure storage, never in the DB.
class EmailSync {
  EmailSync(
    this._db,
    this._ingest,
    this._settings,
    this._secrets, {
    SourceFactory? sources,
    Future<void> Function(String email, String password)? verifyImap,
    GoogleAuth? google,
    this.onLive,
  }) : _google = google,
       _sources =
           sources ??
           ((a, secret) async => switch (a.authType) {
             EmailAuthType.imap when secret != null => ImapSource(
               email: a.email,
               password: secret,
             ),
             EmailAuthType.oauth when google != null => google.gmail(a.email),
             _ => null,
           }),
       _verifyImap =
           verifyImap ?? ((e, p) => ImapSource(email: e, password: p).verify());

  final AppDatabase _db;
  final IngestionService _ingest;
  final SettingsRepository _settings;
  final FlutterSecureStorage _secrets;
  final SourceFactory _sources;
  final Future<void> Function(String email, String password) _verifyImap;
  final GoogleAuth? _google;

  /// After a sync stored mail; rows created since the given time are new.
  final Future<void> Function(DateTime since)? onLive;

  static String _secretKey(String id) => 'email.secret.$id';
  static String _sinceKey(String id) => 'device.email.$id.since';
  static String _errorKey(String id) => 'device.email.$id.error';

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() run) {
    final next = _tail.then((_) => run());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Stream<List<EmailAccountView>> watch() =>
      (_db.select(_db.emailAccounts)
            ..where((a) => a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .watch()
          .asyncMap(
            (rows) async => [
              for (final r in rows)
                EmailAccountView(
                  r,
                  error: _nonEmpty(await _settings.get(_errorKey(r.id))),
                ),
            ],
          );

  Future<bool> get hasAccounts async =>
      (await (_db.select(
            _db.emailAccounts,
          )..where((a) => a.deletedAt.isNull() & a.enabled.equals(true))).get())
          .isNotEmpty;

  /// Checks the app password, saves the inbox and imports from [since].
  /// Throws [EmailAuthException] when the login is refused.
  Future<int> addImap({
    required String email,
    required String appPassword,
    required DateTime since,
  }) async {
    final address = email.trim().toLowerCase();
    final password = appPassword.replaceAll(' ', '');
    await _verifyImap(address, password);
    final id = await _upsert(address, EmailAuthType.imap);
    await _secrets.write(key: _secretKey(id), value: password);
    await _settings.set(_sinceKey(id), since.toIso8601String());
    return syncAll();
  }

  /// Saves a Gmail inbox the owner just signed in to (checking the token
  /// reads mail) and imports from [since].
  Future<int> addGoogle({
    required String email,
    required DateTime since,
  }) async {
    final google = _google;
    if (google == null) throw StateError('Google sign-in not configured');
    final address = email.trim().toLowerCase();
    await google.gmail(address).verify();
    final id = await _upsert(address, EmailAuthType.oauth);
    await _settings.set(_sinceKey(id), since.toIso8601String());
    return syncAll();
  }

  /// Revives a disconnected inbox of the same address + method, or adds one.
  Future<String> _upsert(String address, EmailAuthType type) async {
    final existing =
        await (_db.select(_db.emailAccounts)..where(
              (a) => a.email.equals(address) & a.authType.equalsValue(type),
            ))
            .getSingleOrNull();
    if (existing == null) {
      return (await _db
              .into(_db.emailAccounts)
              .insertReturning(
                EmailAccountsCompanion.insert(email: address, authType: type),
              ))
          .id;
    }
    await (_db.update(
      _db.emailAccounts,
    )..where((a) => a.id.equals(existing.id))).write(
      EmailAccountsCompanion(
        deletedAt: const Value(null),
        enabled: const Value(true),
        syncCursor: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return existing.id;
  }

  /// Forget the inbox and its password (or Google access, when it was the
  /// last Google inbox). Payments it logged stay.
  Future<void> remove(String id) async {
    await (_db.update(_db.emailAccounts)..where((a) => a.id.equals(id))).write(
      EmailAccountsCompanion(
        deletedAt: Value(DateTime.now()),
        enabled: const Value(false),
        syncCursor: const Value(null),
      ),
    );
    await _secrets.delete(key: _secretKey(id));
    final google = _google;
    if (google == null) return;
    final oauthLeft =
        await (_db.select(_db.emailAccounts)..where(
              (a) =>
                  a.deletedAt.isNull() &
                  a.authType.equalsValue(EmailAuthType.oauth),
            ))
            .get();
    // Drive backup signs in through Google too; keep its access.
    final backupOn = await _settings.get(BackupService.account) != null;
    if (oauthLeft.isEmpty && !backupOn) {
      try {
        await google.disconnect();
      } catch (e) {
        debugPrint('k: Google disconnect failed: $e');
      }
    }
  }

  /// Foreground top-up: sync when the oldest inbox is older than [maxAge].
  Future<int> syncIfStale(Duration maxAge) async {
    final accounts = await (_db.select(
      _db.emailAccounts,
    )..where((a) => a.deletedAt.isNull() & a.enabled.equals(true))).get();
    final cutoff = DateTime.now().subtract(maxAge);
    final stale = accounts.any(
      (a) => a.lastSyncAt == null || a.lastSyncAt!.isBefore(cutoff),
    );
    return stale ? syncAll() : 0;
  }

  /// Every enabled inbox; returns payments logged. Failures are recorded
  /// per inbox (shown in Settings) and don't stop the others.
  Future<int> syncAll() => _serial(() async {
    final started = DateTime.now();
    final accounts = await (_db.select(
      _db.emailAccounts,
    )..where((a) => a.deletedAt.isNull() & a.enabled.equals(true))).get();
    if (accounts.isEmpty) return 0;
    final senders = await _bankSenders();
    var logged = 0;
    for (final a in accounts) {
      try {
        logged += await _syncOne(a, senders);
        await _settings.set(_errorKey(a.id), '');
      } on EmailAuthException catch (e) {
        await _settings.set(_errorKey(a.id), e.message);
      } catch (e, s) {
        debugPrint('k: email sync failed for ${a.email}: $e\n$s');
        await _settings.set(_errorKey(a.id), 'Could not reach the inbox');
      }
    }
    await onLive?.call(started);
    return logged;
  });

  Future<int> _syncOne(EmailAccount a, List<String> senders) async {
    final source = await _sources(
      a,
      await _secrets.read(key: _secretKey(a.id)),
    );
    if (source == null) {
      throw const EmailAuthException('Sign in again to keep reading mail');
    }
    final sinceText = await _settings.get(_sinceKey(a.id));
    final since =
        DateTime.tryParse(sinceText ?? '') ??
        (a.lastSyncAt ?? DateTime.now()).subtract(const Duration(days: 1));
    final result = await source.fetch(
      senders: senders,
      cursor: a.syncCursor,
      since: since,
    );
    var logged = 0;
    for (final e in result.emails) {
      final outcome = await _ingest.ingest(
        IncomingMessage(
          channel: Channel.email,
          sender: e.sender,
          subject: e.subject,
          body: e.body,
          receivedAt: e.receivedAt,
          externalId: e.externalId,
          emailAccountId: a.id,
        ),
      );
      if (outcome == IngestOutcome.transaction) logged++;
    }
    await (_db.update(
      _db.emailAccounts,
    )..where((x) => x.id.equals(a.id))).write(
      EmailAccountsCompanion(
        syncCursor: Value(result.cursor),
        lastSyncAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return logged;
  }

  /// Domains / addresses from the enabled email sender rules.
  Future<List<String>> _bankSenders() async {
    final rules =
        await (_db.select(_db.senderRules)..where(
              (r) =>
                  r.deletedAt.isNull() &
                  r.enabled.equals(true) &
                  r.channel.equalsValue(Channel.email),
            ))
            .get();
    return {for (final r in rules) r.pattern}.toList();
  }
}

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
