import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/subscriptions/subscription_service.dart';
import '../ui/format.dart';

/// Local notifications before a subscription renews: one per plan, at 09:00
/// [SubscriptionView.reminderDays] before its next charge. Rebuilt from
/// scratch whenever plans change, so nothing stale lingers. 0 days = off.
class ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'subscription_reminders',
    'Subscription reminders',
    channelDescription: 'Before a subscription charges you',
  );

  /// UI isolate only; the headless SMS worker never schedules.
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

  Future<void> sync(List<SubscriptionView> active) async {
    if (!_ready) return;
    try {
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
          id: s.id.hashCode & 0x7fffffff,
          scheduledDate: at,
          title: '${s.name} renews ${_when(s.reminderDays)}',
          body: '${inr(s.amountMinor)} on ${dayShort(next)}$account',
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e, st) {
      debugPrint('k: scheduling reminders failed: $e\n$st');
    }
  }

  static String _when(int days) => days == 1 ? 'tomorrow' : 'in $days days';
}
