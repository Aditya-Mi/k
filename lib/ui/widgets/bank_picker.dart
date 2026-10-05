import 'package:flutter/material.dart';

import '../../data/repositories/bank_repository.dart';
import '../theme/k_theme.dart';

/// Sentinel [showBankPicker] returns for "A bank not in k".
const newBankPick = '__new__';

/// "SMS from AXISBK · email from axis.bank.in".
String bankSenders(BankView b) => [
  if (b.wallet) 'Wallet',
  if (b.sms.isNotEmpty) 'SMS from ${b.sms.join(', ')}',
  if (b.email.isNotEmpty) 'email from ${b.email.join(', ')}',
  if (b.sms.isEmpty && b.email.isEmpty)
    b.wallet ? 'learned from Review' : 'No senders yet',
].join(' · ');

/// Searchable bank list (design 03g): your banks first, then the other
/// banks k reads. Pops a bank id, [newBankPick], or null.
Future<String?> showBankPicker(
  BuildContext context, {
  required List<BankView> banks,
  required String title,
  String? subtitle,
  String? selectedId,
  bool allowNew = true,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _BankPicker(
    banks: banks,
    title: title,
    subtitle: subtitle,
    selectedId: selectedId,
    allowNew: allowNew,
  ),
);

class _BankPicker extends StatefulWidget {
  const _BankPicker({
    required this.banks,
    required this.title,
    required this.subtitle,
    required this.selectedId,
    required this.allowNew,
  });

  final List<BankView> banks;
  final String title;
  final String? subtitle;
  final String? selectedId;
  final bool allowNew;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final match = filterBanks(widget.banks, _query);
    final yours = match.where((b) => b.inUse).toList();
    final others = match.where((b) => !b.inUse).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: t.title.copyWith(fontSize: 18)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: t.meta.copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.banks.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: BankSearchField(
                    onChanged: (q) => setState(() => _query = q),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (yours.isNotEmpty && others.isNotEmpty)
                      const BankListLabel('Your banks'),
                    for (final b in yours) _row(b, c),
                    if (others.isNotEmpty && yours.isNotEmpty)
                      const BankListLabel('Other banks k reads'),
                    for (final b in others) _row(b, c),
                    if (widget.allowNew)
                      ListTile(
                        leading: Icon(Icons.add_rounded, color: c.text2),
                        title: const Text('A bank not in k'),
                        subtitle: const Text('Name it once'),
                        onTap: () => Navigator.pop(context, newBankPick),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BankView b, KColors c) => ListTile(
    leading: Icon(bankIcon(b), color: c.text2),
    title: Text(b.name),
    subtitle: Text(bankSenders(b)),
    trailing: b.id == widget.selectedId
        ? const Icon(Icons.check_rounded)
        : null,
    onTap: () => Navigator.pop(context, b.id),
  );
}

IconData bankIcon(BankView b) => b.wallet
    ? Icons.account_balance_wallet_outlined
    : Icons.account_balance_outlined;

/// Name or sender contains the query ("hdfc", "sbiinb", "kotak.com").
List<BankView> filterBanks(List<BankView> banks, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return banks;
  return [
    for (final b in banks)
      if (b.name.toLowerCase().contains(q) ||
          b.sms.any((s) => s.toLowerCase().contains(q)) ||
          b.email.any((s) => s.toLowerCase().contains(q)))
        b,
  ];
}

/// Pill search field on surface-2 (designs 03g, 06k).
class BankSearchField extends StatelessWidget {
  const BankSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search banks and wallets',
        prefixIcon: Icon(Icons.search_rounded, color: c.text2),
        filled: true,
        fillColor: c.surface2,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// "Your banks" / "Other banks k reads · 29" section label.
class BankListLabel extends StatelessWidget {
  const BankListLabel(this.text, {super.key, this.horizontal = 20});

  final String text;
  final double horizontal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 4),
    child: Text(
      text,
      style: context.kt.label.copyWith(fontSize: 12.5, color: context.k.text2),
    ),
  );
}
