import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:txn_parser/txn_parser.dart' show Direction, parseAmountMinor;

import '../../widgets/k_sheet.dart';

import '../categories/category_edit_screen.dart';
import '../../../data/db/app_database.dart' hide ParserTemplate, SenderRule;
import '../../../data/ingest/ingestion_service.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt.dart';

/// A payment no SMS or email reported, e.g. a checkout whose receipt went to
/// another inbox (design 09). If the bank's message turns up later for the
/// same account and amount, it merges into this row.
class AddPaymentScreen extends StatefulWidget {
  const AddPaymentScreen({super.key});

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

/// The "Not in k" choice in the account sheet (no account, no balance).
const _noAccount = '';

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final _ledger = getIt<LedgerRepository>();
  var _direction = Direction.debit;
  int? _amount;
  String _payee = '';

  /// Null → not picked yet; [_noAccount] → not tracked.
  String? _accountId;
  List<AccountView> _accounts = const [];
  Category? _category;
  DateTime _when = DateTime.now();
  String _note = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ledger.watchAccounts().first.then((a) {
      if (!mounted) return;
      setState(() {
        _accounts = a;
        // One account → nothing to choose.
        if (a.length == 1) _accountId = a.single.id;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _editAmount());
  }

  bool get _ready => _amount != null && _accountId != null && !_saving;

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
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Symbols.edit, size: 16, color: c.text2),
      ],
    );
    final account = _accountId == null
        ? null
        : _accountId == _noAccount
        ? 'Not in k'
        : _accounts.where((a) => a.id == _accountId).firstOrNull?.short;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Symbols.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _DirectionToggle(
              value: _direction,
              onChanged: (d) => setState(() => _direction = d),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _editAmount,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _amount == null ? '₹0' : inr(_amount!, paise: true),
                    style: t.amountHero.copyWith(
                      color: _amount == null ? c.text3 : c.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Symbols.edit, size: 20, color: c.text2),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FieldRow(
            label: _direction == Direction.debit ? 'Payee' : 'From',
            onTap: _editPayee,
            value: value(_payee.isEmpty ? null : _payee, 'Who'),
          ),
          FieldRow(
            label: 'Account',
            onTap: _editAccount,
            value: value(account, 'Pick'),
          ),
          FieldRow(
            label: 'Category',
            onTap: _editCategory,
            value: value(_category?.name, 'From the payee'),
          ),
          FieldRow(
            label: 'When',
            onTap: _editWhen,
            value: value('${dayShort(_when)}, ${hhmm(_when)}', ''),
          ),
          FieldRow(
            label: 'Note',
            onTap: _editNote,
            value: value(_note.isEmpty ? null : _note, 'Optional'),
          ),
          const SizedBox(height: 20),
          Text(
            'A matching bank message that arrives later merges into this.',
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
          onPressed: _ready ? _save : null,
          icon: const Icon(Symbols.check, size: 20),
          label: const Text('Save payment'),
        ),
      ),
    );
  }

  Future<void> _editAmount() async {
    final v = await promptText(
      context,
      title: 'Amount',
      initial: _amount == null ? '' : (_amount! / 100).toStringAsFixed(2),
      numeric: true,
    );
    final minor = v == null ? null : parseAmountMinor(v);
    if (minor != null && minor > 0) setState(() => _amount = minor);
  }

  Future<void> _editPayee() async {
    final v = await promptText(
      context,
      title: _direction == Direction.debit ? 'Payee' : 'From',
      initial: _payee,
      hint: 'e.g. Hostinger',
    );
    if (v != null) setState(() => _payee = v.trim());
  }

  Future<void> _editAccount() async {
    final picked = await showKSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Account', style: context.kt.title),
              ),
            ),
            for (final a in _accounts)
              ListTile(
                leading: Icon(
                  a.isCash
                      ? Symbols.payments
                      : a.isCard
                      ? Symbols.credit_card
                      : Symbols.account_balance_wallet,
                ),
                title: Text(a.short),
                subtitle: Text(a.isCash ? 'Cash in hand' : a.long),
                trailing: a.id == _accountId ? const Icon(Symbols.check) : null,
                onTap: () => Navigator.pop(context, a.id),
              ),
            ListTile(
              leading: const Icon(Symbols.help),
              title: const Text('Not in k'),
              subtitle: const Text('Not counted in any balance'),
              trailing: _accountId == _noAccount
                  ? const Icon(Symbols.check)
                  : null,
              onTap: () => Navigator.pop(context, _noAccount),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  Future<void> _editCategory() async {
    final categories = await _ledger.watchCategories().first;
    if (!mounted) return;
    final picked = await showKSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final cat in categories)
                ListTile(
                  leading: Icon(categoryIcon(cat.icon), color: context.k.text2),
                  title: Text(cat.name),
                  trailing: cat.id == _category?.id
                      ? const Icon(Symbols.check)
                      : null,
                  onTap: () => Navigator.pop(context, cat),
                ),
              newCategoryTile(context, (c) => c),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _editWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: 'When',
      initialDate: _when,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    final t = time ?? TimeOfDay.fromDateTime(_when);
    setState(
      () => _when = DateTime(day.year, day.month, day.day, t.hour, t.minute),
    );
  }

  Future<void> _editNote() async {
    final v = await promptText(context, title: 'Note', initial: _note);
    if (v != null) setState(() => _note = v.trim());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await getIt<IngestionService>().addManual(
      direction: _direction,
      amountMinor: _amount!,
      occurredAt: _when,
      accountId: _accountId == _noAccount ? null : _accountId,
      payee: _payee,
      categoryId: _category?.id,
      note: _note,
    );
    if (mounted) Navigator.pop(context);
  }
}

/// Paid | Received pill (design 09).
class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.value, required this.onChanged});

  final Direction value;
  final ValueChanged<Direction> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    Widget seg(Direction d, String label) {
      final on = d == value;
      return Material(
        color: on ? c.surface3 : Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => onChanged(d),
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (on) ...[
                    Icon(Symbols.check, size: 18, color: c.text),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: t.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: on ? c.text : c.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Direction',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: c.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg(Direction.debit, 'Paid'),
            const SizedBox(width: 2),
            seg(Direction.credit, 'Received'),
          ],
        ),
      ),
    );
  }
}
