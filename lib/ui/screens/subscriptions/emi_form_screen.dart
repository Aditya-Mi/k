import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/db/enums.dart';
import '../../../data/emis/emi_schedule.dart';
import '../../../data/emis/emi_service.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt.dart';
import 'subscription_parts.dart';

/// Convert a card payment to EMI (design 13b), add a loan EMI (13c), or
/// edit either.
class EmiFormScreen extends StatefulWidget {
  const EmiFormScreen.convert({super.key, required TxnView this.purchase})
    : emi = null,
      kind = EmiKind.card;

  const EmiFormScreen.loan({super.key})
    : purchase = null,
      emi = null,
      kind = EmiKind.loan;

  EmiFormScreen.edit({super.key, required EmiView this.emi})
    : purchase = null,
      kind = emi.row.kind;

  final TxnView? purchase;
  final EmiView? emi;
  final EmiKind kind;

  @override
  State<EmiFormScreen> createState() => _EmiFormScreenState();
}

class _EmiFormScreenState extends State<EmiFormScreen> {
  final _service = getIt<EmiService>();
  late String _name;
  late int _count;
  int? _each;
  bool _eachEdited = false;
  late DateTime? _next;
  late int _paid;
  late bool _spread;
  String? _accountId;
  int? _reminder;
  int _defaultReminder = 3;
  bool _saving = false;
  List<AccountView> _accounts = const [];

  bool get _card => widget.kind == EmiKind.card;
  bool get _editing => widget.emi != null;

  @override
  void initState() {
    super.initState();
    final e = widget.emi;
    final p = widget.purchase;
    final now = DateTime.now();
    if (e != null) {
      _name = e.name;
      _count = e.row.count;
      _each = e.row.amountMinor;
      _eachEdited = true;
      _paid = e.paid;
      _next = e.isCard ? e.row.firstDueAt : (e.nextDueAt ?? e.endsAt);
      _spread = e.row.spread;
      _accountId = e.row.accountId;
      _reminder = e.row.reminderDays;
    } else if (p != null) {
      _name = p.payee;
      _count = 12;
      _each = (p.amountMinor / 12).round();
      _paid = 0;
      // Usually the first instalment lands on the next statement.
      _next = addMonths(DateTime(now.year, now.month, p.occurredAt.day), 1);
      _spread = true;
      _accountId = p.account?.id;
    } else {
      _name = '';
      _count = 12;
      _paid = 0;
      _next = null;
      _spread = true;
    }
    _service.defaultReminder().then((d) {
      if (mounted) setState(() => _defaultReminder = d);
    });
    if (!_card) {
      getIt<LedgerRepository>().watchAccounts().first.then((a) {
        if (!mounted) return;
        setState(
          () => _accounts = [
            for (final x in a)
              if (!x.isCreditCard && !x.isCash) x,
          ],
        );
      });
      if (!_editing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _editName());
      }
    }
  }

  int? get _purchaseMinor =>
      widget.purchase?.amountMinor ?? widget.emi?.purchaseMinor;

  bool get _ready =>
      _name.trim().isNotEmpty &&
      _each != null &&
      _count > 0 &&
      _next != null &&
      _paid < _count;

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
    final purchase = _purchaseMinor;
    final extra = purchase == null || _each == null
        ? null
        : _each! * _count - purchase;
    final account = _accounts.where((a) => a.id == _accountId).firstOrNull;
    final title = _editing
        ? (_card ? 'Card EMI' : 'Loan EMI')
        : (_card ? 'Convert to EMI' : 'Add a loan EMI');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.outline),
                ),
                child: Icon(
                  _card ? Icons.credit_card_rounded : Icons.home_outlined,
                  size: 26,
                  color: c.text2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        _name.isEmpty ? 'New loan' : _name,
                        if (purchase != null) inr(purchase),
                      ].join(' · '),
                      style: t.headline.copyWith(
                        color: _name.isEmpty ? c.text3 : c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _card
                          ? [
                              widget.purchase?.account?.long ??
                                  widget.emi?.account?.long ??
                                  'Credit card',
                              if (widget.purchase != null)
                                dayMonth(widget.purchase!.occurredAt),
                            ].join(' · ')
                          : 'Paid from your bank account each month',
                      style: t.meta,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!_card)
            FieldRow(
              label: 'Name',
              onTap: _editName,
              value: value(_name.isEmpty ? null : _name, 'e.g. Home loan'),
            ),
          if (!_card)
            FieldRow(
              label: 'From',
              onTap: _pickAccount,
              value: value(account?.long ?? 'Not in k', ''),
            ),
          FieldRow(
            label: _card ? 'Months' : 'EMIs in all',
            onTap: _editCount,
            value: value('$_count', ''),
          ),
          FieldRow(
            label: 'Each EMI',
            onTap: _editEach,
            value: value(_each == null ? null : inr(_each!), 'Enter'),
          ),
          if (extra != null)
            FieldRow(
              label: 'Interest and fees',
              value: Text(
                extra.abs() < _count * 100 ? 'None' : inr(extra),
                style: t.body.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          if (!_card)
            FieldRow(
              label: 'Paid so far',
              onTap: _editPaid,
              value: value('$_paid', ''),
            ),
          FieldRow(
            label: _card ? 'First EMI' : 'Next EMI',
            onTap: _editNext,
            value: value(
              _next == null ? null : dayShort(_next!),
              'Pick a date',
            ),
          ),
          if (_card)
            FieldRow(
              label: 'Count as spent',
              onTap: _editSpread,
              value: value(
                _spread ? 'Each EMI, monthly' : 'Full amount once',
                '',
              ),
            ),
          if (!_card)
            FieldRow(
              label: 'Remind me',
              onTap: _editReminder,
              value: value(reminderLabel(_reminder ?? _defaultReminder), ''),
            ),
          const SizedBox(height: 20),
          Text(
            _card
                ? 'Each month the bank bills ${_each == null ? 'an EMI' : inr(_each!)} '
                      'on this card. k links those charges to this EMI and stops '
                      'after $_count. '
                      '${_spread ? 'The purchase is spread across the months, not counted at once.' : 'The purchase counts once; the monthly charges don\'t count again.'}'
                : 'When the debit arrives, k links it: a payment from this '
                      'account of about this amount, within a week of the date. '
                      'Most loan EMIs come as NACH or ECS debits.',
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
        child: Row(
          children: [
            if (_editing) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _saving ? null : _remove,
                  child: const Text('Stop tracking'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _ready && !_saving ? _save : null,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Save EMI'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName() async {
    final v = await promptText(
      context,
      title: 'Name',
      initial: _name,
      hint: 'e.g. Home loan, Car loan',
    );
    if (v != null) setState(() => _name = v.trim());
  }

  Future<void> _pickAccount() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final a in _accounts)
              ListTile(
                title: Text(a.long),
                trailing: a.id == _accountId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, a.id),
              ),
            ListTile(
              title: const Text('Not in k'),
              subtitle: const Text('k can\'t link its debits'),
              trailing: _accountId == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _accountId = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _editCount() async {
    int? n;
    if (_card) {
      n = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in const [3, 6, 9, 12, 18, 24])
                ListTile(
                  title: Text('$m months'),
                  trailing: m == _count
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, m),
                ),
              ListTile(
                title: const Text('Other'),
                onTap: () => Navigator.pop(context, -1),
              ),
            ],
          ),
        ),
      );
      if (n == null || !mounted) return;
    }
    if (n == null || n < 0) {
      final v = await promptText(
        context,
        title: _card ? 'Months' : 'EMIs in all',
        initial: '$_count',
        numeric: true,
      );
      n = int.tryParse(v ?? '');
    }
    if (n == null || n <= 0) return;
    final count = n;
    setState(() {
      _count = count;
      final p = _purchaseMinor;
      if (p != null && !_eachEdited) _each = (p / count).round();
    });
  }

  Future<void> _editEach() async {
    final v = await promptText(
      context,
      title: 'Each EMI',
      initial: _each == null ? '' : (_each! / 100).toStringAsFixed(0),
      numeric: true,
    );
    final minor = v == null ? null : parseAmountMinor(v);
    if (minor != null && minor > 0) {
      setState(() {
        _each = minor;
        _eachEdited = true;
      });
    }
  }

  Future<void> _editPaid() async {
    final v = await promptText(
      context,
      title: 'EMIs paid so far',
      initial: '$_paid',
      numeric: true,
    );
    final n = int.tryParse(v ?? '');
    if (n != null && n >= 0) setState(() => _paid = n);
  }

  Future<void> _editNext() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: _card ? 'First EMI' : 'Next EMI',
      initialDate: _next ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 3),
    );
    if (day != null) setState(() => _next = day);
  }

  Future<void> _editSpread() async {
    final v = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Each EMI, monthly'),
              subtitle: const Text('The purchase is spread over the months'),
              trailing: _spread ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              title: const Text('Full amount once'),
              subtitle: const Text('In the month you bought it'),
              trailing: !_spread ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _spread = v);
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
    final e = widget.emi;
    final p = widget.purchase;
    if (e != null) {
      await _service.update(
        e.id,
        name: _card ? null : _name.trim(),
        amountMinor: _each,
        count: _count,
        // A card EMI's date is its first instalment; a loan's the next one.
        paid: _card ? 0 : _paid,
        nextDueAt: _next,
        spread: _card ? _spread : null,
        reminderDays: _card ? null : () => _reminder,
        accountId: _card ? null : () => _accountId,
      );
    } else if (p != null) {
      await _service.convertPurchase(
        transactionId: p.id,
        count: _count,
        amountMinor: _each!,
        firstDueAt: _next!,
        spread: _spread,
      );
    } else {
      await _service.addLoan(
        name: _name.trim(),
        accountId: _accountId,
        amountMinor: _each!,
        count: _count,
        paid: _paid,
        nextDueAt: _next!,
        reminderDays: _reminder,
      );
      // Reminders need this on Android 13+.
      await Permission.notification.request();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop tracking this EMI?'),
        content: Text(
          _card
              ? 'The purchase counts as spent once again, in the month you '
                    'bought it.'
              : 'Its debits stay logged as payments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop tracking'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.remove(widget.emi!.id);
    if (mounted) Navigator.pop(context);
  }
}
