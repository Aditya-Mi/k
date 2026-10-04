import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/db/app_database.dart';
import '../data/db/enums.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/subscriptions/subscription_service.dart';
import '../ui/format.dart';

/// Everything k posts to the notification shade, all built on the phone:
/// - subscription reminders: 09:00, N days before each plan's next charge
///   (rebuilt from scratch whenever plans change; 0 days = off)
/// - payment logged: one per payment from a live SMS
/// - needs review: one running notice while messages wait in Review
/// Live alerts come only from the receiver's queue, never from inbox
/// catch-up or history import, and not while k is on screen. Content is
/// hidden on a locked screen.
class KNotifications {
  KNotifications(this._db, this._ledger, this._settings);

  final AppDatabase _db;
  final LedgerRepository _ledger;
  final SettingsRepository _settings;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Set by the UI lifecycle; the headless SMS worker leaves it false.
  bool appVisible = false;

  static const paymentsKey = 'device.notify.payments';
  static const reviewKey = 'device.notify.review';

  static const _reviewId = 1;

  static const _reminders = AndroidNotificationDetails(
    'subscription_reminders',
    'Subscription reminders',
    channelDescription: 'Before a subscription charges you',
    visibility: NotificationVisibility.private,
  );
  static const _payments = AndroidNotificationDetails(
    'payments',
    'Payment logged',
    channelDescription: 'Each payment as its bank SMS arrives',
    visibility: NotificationVisibility.private,
  );
  static const _review = AndroidNotificationDetails(
    'review',
    'Needs review',
    channelDescription: 'A bank message could not be read',
    visibility: NotificationVisibility.private,
    onlyAlertOnce: true,
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_k'),
      ),
    );
    _ready = true;
  }

  Future<bool> _on(String key) async => await _settings.get(key) != 'false';

  // ------------------------------------------------------------ reminders

  Future<void> syncReminders(List<SubscriptionView> active) async {
    if (!_ready) return;
    try {
      // Only reminders are scheduled ahead; live alerts are shown at once.
      await _plugin.cancelAllPendingNotifications();
      final now = tz.TZDateTime.now(tz.local);
      for (final s in active) {
        final next = s.row.nextExpectedAt;
        if (next == null || s.reminderDays <= 0) continue;
        final day = next.subtract(Duration(days: s.reminderDays));
        final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, 9);
        if (!at.isAfter(now)) continue;
        final account = s.account == null ? '' : ' · ${s.account!.short}';
        await _plugin.zonedSchedule(
          id: _idFor('r${s.id}'),
          scheduledDate: at,
          title: '${s.name} renews ${_when(s.reminderDays)}',
          body: '${inr(s.amountMinor)} on ${dayShort(next)}$account',
          notificationDetails: const NotificationDetails(android: _reminders),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e, st) {
      debugPrint('k: scheduling reminders failed: $e\n$st');
    }
  }

  static String _when(int days) => days == 1 ? 'tomorrow' : 'in $days days';

  // ---------------------------------------------------------- live alerts

  /// After a live SMS drain that started at [since].
  Future<void> notifyNew(DateTime since) async {
    if (!_ready || appVisible) return;
    try {
      if (await _on(paymentsKey)) await _notifyPayments(since);
      if (await _on(reviewKey)) await _notifyReview(since);
    } catch (e, st) {
      debugPrint('k: live notification failed: $e\n$st');
    }
  }

  Future<void> _notifyPayments(DateTime since) async {
    for (final t in await _ledger.loggedSince(since)) {
      final amount = inr(t.amountMinor, paise: true);
      final title = t.isTransfer
          ? 'Self transfer $amount'
          : t.isDebit
          ? '$amount paid to ${t.payee}'
          : '$amount received from ${t.payee}';
      final body = [
        if (t.isTransfer) t.transferRoute else ?t.account?.short,
        hhmm(t.occurredAt),
        if (!t.isTransfer) ?t.category?.name,
      ].join(' · ');
      await _plugin.show(
        id: _idFor('p${t.id}'),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _payments),
      );
    }
  }

  Future<void> _notifyReview(DateTime since) async {
    final r = _db.rawMessages;
    final fresh = r.id.count();
    final added =
        await (_db.selectOnly(r)
              ..addColumns([fresh])
              ..where(
                r.deletedAt.isNull() &
                    r.status.equalsValue(RawMessageStatus.needsReview) &
                    r.createdAt.isBiggerOrEqualValue(since),
              ))
            .map((row) => row.read(fresh) ?? 0)
            .getSingle();
    if (added == 0) return;
    final waiting = await _ledger.watchReviewCount().first;
    await _plugin.show(
      id: _reviewId,
      title: waiting == 1
          ? 'A bank message needs a look'
          : '$waiting bank messages need a look',
      body: 'k could not read it. Open Review to mark the amount.',
      notificationDetails: const NotificationDetails(android: _review),
    );
  }

  /// Review was opened or emptied: the running notice goes.
  Future<void> clearReview() async {
    if (_ready) await _plugin.cancel(id: _reviewId);
  }

  /// Never 1 (the review notice).
  static int _idFor(String key) => (key.hashCode & 0x7fffffff) | 2;
}
