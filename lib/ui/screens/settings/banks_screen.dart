import 'package:flutter/material.dart';

import '../../../data/repositories/bank_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/bank_picker.dart';
import 'bank_settings.dart';

/// Every bank k reads (design 06k): yours first, then the rest of the
/// catalogue, searchable. Tap one to add a sender.
class BanksScreen extends StatefulWidget {
  const BanksScreen({super.key});

  @override
  State<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends State<BanksScreen> {
  final _banks = getIt<BankRepository>().watchBanks();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: const Text('Banks')),
      body: StreamBuilder<List<BankView>>(
        stream: _banks,
        builder: (context, snap) {
          final all = snap.data ?? const <BankView>[];
          final match = filterBanks(all, _query);
          final yours = match.where((b) => b.inUse).toList();
          final others = match.where((b) => !b.inUse).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 4),
              BankSearchField(onChanged: (q) => setState(() => _query = q)),
              if (yours.isNotEmpty)
                BankListLabel('Your banks · ${yours.length}', horizontal: 0),
              for (final b in yours) _BankRow(bank: b, banks: all),
              if (others.isNotEmpty)
                BankListLabel(
                  'Other banks k reads · ${others.length}',
                  horizontal: 0,
                ),
              for (final b in others) _BankRow(bank: b, banks: all),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                child: Text(
                  'Tap a bank to add a sender.',
                  style: t.meta.copyWith(color: c.text2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({required this.bank, required this.banks});

  final BankView bank;
  final List<BankView> banks;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final accounts = bank.accounts == 0
        ? ''
        : '${bank.accounts} ${bank.accounts == 1 ? 'account' : 'accounts'} · ';
    return InkWell(
      onTap: () => addBankSender(context, banks, bank: bank),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outline)),
        ),
        child: Row(
          children: [
            Icon(bankIcon(bank), color: c.text2),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bank.name,
                    style: t.body.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text('$accounts${bankSenders(bank)}', style: t.meta),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.text3, size: 20),
          ],
        ),
      ),
    );
  }
}
