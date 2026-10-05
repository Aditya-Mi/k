import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/db/enums.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/rosette.dart';
import '../../widgets/text_prompt.dart';
import 'subscription_parts.dart';

/// A plan added before any charge is logged (design 04d). Its first charge
/// links itself when it arrives (see SubscriptionService._matchFirstCharge).
class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _service = getIt<SubscriptionService>();
  String _name = '';
  int? _amount;
  var _frequency = SubscriptionFrequency.monthly;
  DateTime? _next;

  /// Null → the global default.
  int? _reminder;
  int _defaultReminder = 3;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service.defaultReminderDays().then((d) {
      if (mounted) setState(() => _defaultReminder = d);
    });
    // Ask for the name straight away; it is the one thing k can't guess.
    WidgetsBinding.instance.addPostFrameCallback((_) => _editName());
  }

  bool get _ready =>
      _name.trim().isNotEmpty && _amount != null && _next != null;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    Widget value(String? v, String placeholder) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            v ?? placeholder,
            style: t.body.copyWith(
              fontWeight: v == null ? FontWeight.w400 : FontWeight.w500,
              color: v == null ? c.text3 : c.text,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.edit_outlined, size: 16, color: c.text2),
      ],
    );
    final name = _name.trim();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add subscription'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Row(
            children: [
              name.isEmpty
                  ? Rosette(size: 64, color: c.text3, strokeWidth: 0.6)
                  : Seal(name: name, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'New subscription' : name,
                      style: t.headline.copyWith(
                        color: name.isEmpty ? c.text3 : c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Its seal is made from the name', style: t.meta),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FieldRow(
            label: 'Name',
            onTap: _editName,
            value: value(name.isEmpty ? null : name, 'e.g. Apple Music'),
          ),
          FieldRow(
            label: 'Amount',
            onTap: _editAmount,
            value: value(_amount == null ? null : inr(_amount!), 'Enter'),
          ),
          FieldRow(
            label: 'Repeats',
            onTap: _editFrequency,
            value: value(frequencyLabel(_frequency, 30), ''),
          ),
          FieldRow(
            label: 'Next charge',
            onTap: _editNext,
            value: value(
              _next == null ? null : dayShort(_next!),
              'Pick a date',
            ),
          ),
          FieldRow(
            label: 'Remind me',
            onTap: _editReminder,
            value: value(reminderLabel(_reminder ?? _defaultReminder), ''),
          ),
          const SizedBox(height: 20),
          Text(
            'k links a payment to this payee near this amount and date.',
            style: t.meta.copyWith(color: c.text3, height: 1.35),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface1,
          border: Border(top: BorderSide(color: c.outline)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _ready && !_saving ? _save : null,
          icon: const Icon(Icons.check_rounded, size: 20),
          label: const Text('Track it'),
        ),
      ),
    );
  }

  Future<void> _editName() async {
    final v = await promptText(
      context,
      title: 'Name',
      initial: _name,
      hint: 'As your bank shows the payee, e.g. Apple',
    );
    if (v != null) setState(() => _name = v.trim());
  }

  Future<void> _editAmount() async {
    final v = await promptText(
      context,
      title: 'Amount',
      initial: _amount == null ? '' : (_amount! / 100).toStringAsFixed(0),
      numeric: true,
    );
    final minor = v == null ? null : parseAmountMinor(v);
    if (minor != null && minor > 0) setState(() => _amount = minor);
  }

  Future<void> _editFrequency() async {
    final picked = await showModalBottomSheet<SubscriptionFrequency>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in const [
              SubscriptionFrequency.monthly,
              SubscriptionFrequency.quarterly,
              SubscriptionFrequency.halfYearly,
              SubscriptionFrequency.yearly,
            ])
              ListTile(
                title: Text(frequencyLabel(f, 30)),
                trailing: f == _frequency
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _frequency = picked);
  }

  Future<void> _editNext() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = await showDatePicker(
      context: context,
      helpText: 'Next charge',
      initialDate: _next ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 2),
    );
    if (day != null) setState(() => _next = day);
  }

  Future<void> _editReminder() async {
    final d = await pickReminder(
      context,
      current: _reminder ?? _defaultReminder,
      defaultDays: _defaultReminder,
      usingDefault: _reminder == null,
    );
    if (d != null) setState(() => _reminder = d < 0 ? null : d);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _service.addManual(
      name: _name,
      amountMinor: _amount!,
      frequency: _frequency,
      next: _next!,
      reminderDays: _reminder,
    );
    // Reminders need this on Android 13+.
    await Permission.notification.request();
    await _service.refresh();
    if (mounted) Navigator.pop(context);
  }
}
