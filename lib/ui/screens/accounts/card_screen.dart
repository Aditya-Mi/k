import 'package:flutter/material.dart';

import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_row.dart';
import '../subscriptions/emi_parts.dart';
import '../txn_detail/txn_detail_screen.dart';
import 'accounts_screen.dart';

/// One credit card (design 12b): what's owed against the limit, the last
/// bill paid, its EMIs and recent payments.
class CardScreen extends StatelessWidget {
  const CardScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final now = DateTime.now();
    final recent = getIt<LedgerRepository>().watchTransactions(
      TxnFilter(
        from: DateTime(now.year, now.month - 3),
        to: DateTime(now.year + 1),
        accountIds: {accountId},
      ),
    );
    return StreamBuilder<List<AccountRowData>>(
      stream: AccountsScreen.rows(),
      builder: (context, snap) {
        final all = snap.data ?? const <AccountRowData>[];
        final row = all.where((r) => r.account.id == accountId).firstOrNull;
        if (row == null) return const Scaffold();
        final a = row.account;
        final b = row.balance;
        final owed = a.owedMinor(b?.amountMinor);
        final limit = a.creditLimitMinor;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(a.nickname ?? a.short),
            actions: [
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => accountActions(context, row, all),
              ),
            ],
          ),
          body: StreamBuilder<List<TxnView>>(
            stream: recent,
            builder: (context, txSnap) {
              final txns = txSnap.data ?? const <TxnView>[];
              final lastBill = txns
                  .where((x) => x.isCardBill && !x.isDebit)
                  .firstOrNull;
              // Txn rows carry their own 16dp gutter; the rest is padded.
              return ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          owed == null ? 'Available limit' : 'You owe',
                          style: t.meta.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          owed != null
                              ? inr(owed, paise: true)
                              : b == null
                              ? '—'
                              : inr(b.amountMinor, paise: true),
                          style: t.amountHero,
                        ),
                        if (owed != null && limit != null && limit > 0) ...[
                          const SizedBox(height: 10),
                          UsedBar(fraction: owed / limit, height: 6),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (owed != null) cardLimitLine(a, b),
                            if (b != null)
                              '${b.source == BalanceSource.bank ? 'bank' : 'set'}, '
                                  '${dayMonth(b.anchorAt)}, ${hhmm(b.anchorAt)}'
                                  '${b.estimated ? ', estimated since' : ''}',
                          ].join(' · '),
                          style: t.meta,
                        ),
                        const SizedBox(height: 12),
                        FieldRow(
                          label: 'Card limit',
                          onTap: () => accountActions(context, row, all),
                          value: Text(
                            limit == null ? 'Set it' : inr(limit),
                            style: t.body.copyWith(
                              color: limit == null ? c.text3 : c.text,
                            ),
                          ),
                        ),
                        FieldRow(
                          label: 'Last bill paid',
                          onTap: lastBill == null
                              ? null
                              : () => _open(context, lastBill.id),
                          value: Text(
                            lastBill == null
                                ? 'None seen yet'
                                : '${inr(lastBill.amountMinor)} · '
                                      '${dayMonth(lastBill.occurredAt)}'
                                      '${lastBill.partnerAccount == null ? '' : ' · from ${lastBill.partnerAccount!.short}'}',
                            style: t.body.copyWith(
                              color: lastBill == null ? c.text3 : c.text,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        if (row.emis.isNotEmpty) ...[
                          EmiHead(emis: row.emis),
                          for (final e in row.emis)
                            EmiRow(emi: e, showAccount: false),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 4),
                          child: Text('Recent', style: t.title),
                        ),
                        if (txns.isEmpty)
                          Text(
                            'No payments in the last three months',
                            style: t.meta,
                          ),
                      ],
                    ),
                  ),
                  for (final x in txns.take(30))
                    TxnRow(txn: x, onTap: () => _open(context, x.id)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _open(BuildContext context, String id) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => TxnDetailScreen(txnId: id)));
}
