import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/db/enums.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/bank_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt.dart';

/// Add an account before any message names it (design 10c): bank from the
/// catalogue, type, last 4, nickname, and optionally the balance now.
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _banksStream = getIt<BankRepository>().watchBanks();
  final _last4 = TextEditingController();
  final _nickname = TextEditingController();
  final _balance = TextEditingController();
  final _limit = TextEditingController();
  String? _bankId;

  /// A bank typed in "A bank not in k", created on save.
  String? _newBank;
  var _type = AccountType.savings;
  var _overdrawn = false;
  var _saving = false;

  static const _types = {
    AccountType.savings: 'Savings',
    AccountType.current: 'Current',
    AccountType.creditCard: 'Credit card',
    AccountType.wallet: 'Wallet',
  };

  @override
  void dispose() {
    _last4.dispose();
    _nickname.dispose();
    _balance.dispose();
    _limit.dispose();
    super.dispose();
  }

  bool get _isCard => _type == AccountType.creditCard;
  bool get _needsDigits => _type != AccountType.wallet;

  bool get _ready =>
      (_bankId != null || _newBank != null) &&
      (!_needsDigits || RegExp(r'^\d{4}$').hasMatch(_last4.text.trim()));

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return StreamBuilder<List<BankView>>(
      stream: _banksStream,
      builder: (context, snap) {
        final banks = snap.data ?? const <BankView>[];
        final bankName =
            _newBank ?? banks.where((b) => b.id == _bankId).firstOrNull?.name;
        final digits = _last4.text.trim();
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Add account'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FieldRow(
                label: 'Bank',
                value: SelectButton(
                  label: bankName,
                  onPressed: () => _pickBank(banks),
                ),
              ),
              FieldRow(
                label: 'Type',
                value: SelectButton(label: _types[_type], onPressed: _pickType),
              ),
              const SizedBox(height: 20),
              if (_needsDigits) ...[
                _Label(
                  _isCard
                      ? 'Last 4 digits of the card'
                      : 'Last 4 digits of the account or card',
                ),
                TextField(
                  controller: _last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '1234',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
              ],
              const _Label('Nickname (optional)'),
              TextField(
                controller: _nickname,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Salary account',
                ),
              ),
              if (_isCard) ...[
                const SizedBox(height: 20),
                const _Label('Card limit (optional)'),
                TextField(
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'e.g. 1,00,000',
                    prefixText: '₹ ',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _Label(
                _isCard
                    ? 'Available limit now (optional)'
                    : 'Balance now (optional)',
              ),
              Row(
                children: [
                  if (!_isCard) ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('In credit')),
                        ButtonSegment(value: true, label: Text('Overdrawn')),
                      ],
                      selected: {_overdrawn},
                      onSelectionChanged: (v) =>
                          setState(() => _overdrawn = v.single),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _balance,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: _overdrawn && !_isCard ? '−₹ ' : '₹ ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _needsDigits
                    ? 'Messages naming ··${digits.isEmpty ? '1234' : digits} '
                          'land here.'
                    : 'Wallet messages land here.',
                style: t.meta.copyWith(fontSize: 13, color: c.text2),
              ),
              const SizedBox(height: 24),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.outline)),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _ready && !_saving ? _save : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add account'),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickBank(List<BankView> banks) async {
    final picked = await showBankPicker(
      context,
      banks: banks,
      title: 'Which bank?',
      selectedId: _bankId,
    );
    if (!mounted || picked == null) return;
    if (picked == newBankPick) {
      final name = await promptText(
        context,
        title: 'A bank not in k',
        hint: 'e.g. HDFC Bank',
        help: 'Review asks you to confirm the sender on its first message.',
        action: 'Add',
      );
      if (name == null || name.trim().isEmpty) return;
      setState(() {
        _newBank = name.trim();
        _bankId = null;
      });
    } else {
      setState(() {
        _bankId = picked;
        _newBank = null;
        if (banks.any((b) => b.id == picked && b.wallet)) {
          _type = AccountType.wallet;
        }
      });
    }
  }

  Future<void> _pickType() async {
    final picked = await showModalBottomSheet<AccountType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(key: type, value: label) in _types.entries)
              ListTile(
                title: Text(label),
                trailing: type == _type
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _type = picked;
        if (_isCard) _overdrawn = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final bankId =
          _bankId ?? await getIt<BankRepository>().addBank(_newBank!);
      final typed = parseAmountMinor(_balance.text);
      final id = await getIt<LedgerRepository>().addAccount(
        bankId: bankId,
        type: _type,
        last4: _needsDigits ? _last4.text.trim() : null,
        nickname: _nickname.text,
        balanceMinor: typed == null ? null : (_overdrawn ? -typed : typed),
        creditLimitMinor: _isCard ? parseAmountMinor(_limit.text) : null,
      );
      if (id == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('That account is already in k')),
        );
        return;
      }
      nav.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: context.kt.label.copyWith(fontSize: 13, color: context.k.text2),
    ),
  );
}
