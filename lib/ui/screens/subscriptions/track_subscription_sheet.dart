import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/k_sheet.dart';

import '../../../data/db/enums.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/subscriptions/recurrence.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import 'subscription_parts.dart';

/// "Track as subscription" from one payment (design 02c): pick how often it
/// repeats; the next charge follows from this payment and can be changed.
/// Returns the new plan's id, or null when cancelled.
Future<String?> showTrackSubscriptionSheet(BuildContext context, TxnView txn) =>
    showKSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrackSheet(txn: txn),
    );

class _TrackSheet extends StatefulWidget {
  const _TrackSheet({required this.txn});

  final TxnView txn;

  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  var _frequency = SubscriptionFrequency.monthly;
  DateTime? _pickedNext;
  bool _saving = false;

  /// Next charge after this payment that is still ahead.
  DateTime get _next {
    if (_pickedNext != null) return _pickedNext!;
    var d = nextCharge(widget.txn.occurredAt, _frequency);
    final today = DateTime.now();
    while (d.isBefore(DateTime(today.year, today.month, today.day))) {
      d = nextCharge(d, _frequency);
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final txn = widget.txn;
    final account = txn.account == null ? '' : ' · ${txn.account!.short}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Seal(name: txn.payee),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Track as a subscription', style: t.title),
                      const SizedBox(height: 2),
                      Text(
                        '${txn.payee} · ${inr(txn.amountMinor)}$account',
                        style: t.meta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Repeats', style: t.meta),
            RadioGroup<SubscriptionFrequency>(
              groupValue: _frequency,
              onChanged: (f) => setState(() {
                _frequency = f!;
                _pickedNext = null;
              }),
              child: Column(
                children: [
                  for (final f in const [
                    SubscriptionFrequency.monthly,
                    SubscriptionFrequency.quarterly,
                    SubscriptionFrequency.halfYearly,
                    SubscriptionFrequency.yearly,
                  ])
                    RadioListTile<SubscriptionFrequency>(
                      value: f,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(frequencyLabel(f, 30), style: t.body),
                    ),
                ],
              ),
            ),
            InkWell(
              onTap: _pickDate,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: c.outline),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Next charge',
                        style: t.body.copyWith(color: c.text2),
                      ),
                    ),
                    Text(
                      dayShort(_next),
                      style: t.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 6),
                    Icon(Symbols.edit, size: 16, color: c.text2),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Symbols.check, size: 20),
                  label: const Text('Track it'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: 'Next charge',
      initialDate: _next,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (day != null) setState(() => _pickedNext = day);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final service = getIt<SubscriptionService>();
    final id = await service.trackFromTransaction(
      widget.txn.id,
      _frequency,
      _next,
    );
    // Reminders need this on Android 13+.
    await Permission.notification.request();
    await service.refresh();
    if (mounted) Navigator.pop(context, id);
  }
}
