import 'package:flutter/services.dart';

/// One SMS as handed over by the native side (live queue or inbox read).
class NativeSms {
  const NativeSms({
    required this.sender,
    required this.body,
    required this.timestamp,
    this.queueId,
    this.providerId,
    this.simSlot,
  });

  factory NativeSms.fromMap(Map<Object?, Object?> m) => NativeSms(
    queueId: m['id'] as String?,
    providerId: (m['providerId'] as num?)?.toInt(),
    sender: m['sender']! as String,
    body: m['body']! as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (m['timestamp']! as num).toInt(),
    ),
    simSlot: (m['simSlot'] as num?)?.toInt(),
  );

  /// Id in the native pending queue (live capture only).
  final String? queueId;

  /// SMS content-provider `_id` (inbox reads only).
  final int? providerId;
  final String sender;
  final String body;

  /// Service-centre time — identical for live and inbox copies of one SMS.
  final DateTime timestamp;

  /// 0-based SIM slot.
  final int? simSlot;
}

class InboxPage {
  const InboxPage(this.messages, this.maxId, this.scanned);

  final List<NativeSms> messages;

  /// Highest provider `_id` scanned, including filtered-out personal SMS.
  final int maxId;
  final int scanned;
}

/// Dart side of the `k/sms` channels (see android `SmsChannel.kt`).
class SmsBridge {
  static const _methods = MethodChannel('k/sms');
  static const _events = EventChannel('k/sms_events');

  /// Fires when the receiver queued new SMS while the UI is running.
  Stream<void> get onPending => _events.receiveBroadcastStream().map((_) {});

  Future<List<NativeSms>> drainPending() async {
    final list = await _methods.invokeListMethod<Object?>('drainPending');
    return [for (final m in list ?? const []) NativeSms.fromMap(m! as Map)];
  }

  Future<void> ackPending(List<String> ids) =>
      _methods.invokeMethod('ackPending', ids);

  Future<InboxPage> readInbox({
    required int afterId,
    DateTime? since,
    int limit = 500,
  }) async {
    final r = await _methods.invokeMapMethod<String, Object?>('readInbox', {
      'afterId': afterId,
      'sinceMillis': since?.millisecondsSinceEpoch ?? 0,
      'limit': limit,
    });
    return InboxPage(
      [for (final m in (r!['messages']! as List)) NativeSms.fromMap(m! as Map)],
      (r['maxId']! as num).toInt(),
      (r['scanned']! as num).toInt(),
    );
  }

  Future<int> maxInboxId() async =>
      (await _methods.invokeMethod<num>('maxInboxId'))?.toInt() ?? 0;

  /// Headless worker engine only: tells Kotlin the run finished.
  Future<void> backgroundDone({required bool ok}) =>
      _methods.invokeMethod('backgroundDone', ok);
}
