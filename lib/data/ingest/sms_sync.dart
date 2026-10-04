import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../platform/sms_bridge.dart';
import '../repositories/settings_repository.dart';
import 'ingestion_service.dart';

/// Moves SMS from the native side into the ledger:
/// - live: drain the receiver's queue (ack only what was stored)
/// - catch-up: inbox rows past the saved `_id` cursor (missed broadcasts)
/// - history: first-run import from a chosen date
class SmsSync {
  SmsSync(this._bridge, this._ingest, this._settings, {this.onLive});

  final SmsBridge _bridge;
  final IngestionService _ingest;
  final SettingsRepository _settings;

  /// After a live drain stored messages; rows created since the given time
  /// are what just arrived (catch-up and history never call this).
  final Future<void> Function(DateTime since)? onLive;

  static const _pageSize = 500;

  /// Runs are serialized so live, catch-up and history never interleave.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() run) {
    final next = _tail.then((_) => run());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<int> drainPending() => _serial(() async {
    final pending = await _bridge.drainPending();
    if (pending.isEmpty) return 0;
    final started = DateTime.now();
    final handled = <String>[];
    var logged = 0;
    for (final sms in pending) {
      try {
        if (await _ingest.ingest(_toIncoming(sms)) ==
            IngestOutcome.transaction) {
          logged++;
        }
        handled.add(sms.queueId!);
      } catch (e, s) {
        // Stays queued; retried on the next drain.
        debugPrint('k: ingest failed for queued SMS: $e\n$s');
      }
    }
    await _bridge.ackPending(handled);
    await _markSynced();
    if (handled.isNotEmpty) await onLive?.call(started);
    return logged;
  });

  /// Inbox rows after the cursor. No-op until onboarding set a cursor.
  Future<int> catchUp() => _serial(() async {
    final cursor = await _settings.getInt(SettingsRepository.smsInboxCursor);
    if (cursor == null) return 0;
    final logged = await _scan(afterId: cursor);
    await _markSynced();
    return logged;
  });

  /// First run: import inbox from [since] (null = skip history entirely).
  Future<int> importHistory(
    DateTime? since, {
    void Function(int)? onProgress,
  }) => _serial(() async {
    var logged = 0;
    if (since != null) {
      logged = await _scan(afterId: 0, since: since, onProgress: onProgress);
    }
    // Start live catch-up from the newest SMS, whatever was imported.
    final max = await _bridge.maxInboxId();
    final cursor =
        await _settings.getInt(SettingsRepository.smsInboxCursor) ?? 0;
    if (max > cursor) {
      await _settings.set(SettingsRepository.smsInboxCursor, '$max');
    }
    await _markSynced();
    return logged;
  });

  Future<int> _scan({
    required int afterId,
    DateTime? since,
    void Function(int)? onProgress,
  }) async {
    var cursor = afterId;
    var logged = 0;
    while (true) {
      final page = await _bridge.readInbox(
        afterId: cursor,
        since: since,
        limit: _pageSize,
      );
      for (final sms in page.messages) {
        if (await _ingest.ingest(_toIncoming(sms)) ==
            IngestOutcome.transaction) {
          logged++;
        }
      }
      onProgress?.call(logged);
      if (page.maxId > cursor) {
        cursor = page.maxId;
        // Saved per page: a crash mid-import resumes, never re-reads everything.
        final saved =
            await _settings.getInt(SettingsRepository.smsInboxCursor) ?? 0;
        if (cursor > saved) {
          await _settings.set(SettingsRepository.smsInboxCursor, '$cursor');
        }
      }
      if (page.scanned < _pageSize) break;
    }
    return logged;
  }

  Future<void> _markSynced() => _settings.set(
    SettingsRepository.smsLastSyncAt,
    DateTime.now().toIso8601String(),
  );

  IncomingMessage _toIncoming(NativeSms sms) => IncomingMessage(
    channel: Channel.sms,
    sender: sms.sender,
    body: sms.body,
    receivedAt: sms.timestamp,
    externalId: sms.providerId?.toString(),
    simSlot: sms.simSlot,
  );
}
