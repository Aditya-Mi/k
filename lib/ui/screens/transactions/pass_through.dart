import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/ingest/offset_linker.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/k_sheet.dart';
import '../../widgets/note_chip.dart';

/// "2 may cancel out · Check" on Transactions (design 01f): money in, then
/// most of it out within days. Hidden when there's nothing to ask.
class PassThroughBanner extends StatefulWidget {
  const PassThroughBanner({super.key});

  @override
  State<PassThroughBanner> createState() => _PassThroughBannerState();
}

class _PassThroughBannerState extends State<PassThroughBanner> {
  late final _pairs = getIt<LedgerRepository>().watchPassThroughs();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<(TxnView, TxnView)>>(
    stream: _pairs,
    builder: (context, snap) {
      final pairs = snap.data ?? const [];
      if (pairs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: NoticeBanner(
          icon: Symbols.link,
          text: '${pairs.length} may cancel out',
          detail: 'Money in, then passed on',
          action: 'Check',
          onTap: () => showKSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _PassThroughSheet(stream: _pairs),
          ),
        ),
      );
    },
  );
}

/// "Do these cancel out?" (design 01g): one card per pair, No / Cancels out.
class _PassThroughSheet extends StatelessWidget {
  const _PassThroughSheet({required this.stream});

  final Stream<List<(TxnView, TxnView)>> stream;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: StreamBuilder<List<(TxnView, TxnView)>>(
          stream: stream,
          builder: (context, snap) {
            final pairs = snap.data ?? const [];
            if (snap.hasData && pairs.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.maybePop(context);
              });
            }
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text('Do these cancel out?', style: t.title),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Money in, then most of it out within 3 days.',
                    style: t.meta,
                  ),
                ),
                for (final (credit, debit) in pairs)
                  _PairCard(credit: credit, debit: debit),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.credit, required this.debit});

  final TxnView credit;
  final TxnView debit;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final left = credit.amountMinor - debit.amountMinor;
    Widget line(TxnView v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          NoteChip(
            amountMinor: v.amountMinor,
            style: v.isDebit ? NoteChipStyle.filled : NoteChipStyle.outlined,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              v.payee,
              style: t.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(inrRow(v.amountMinor, plus: !v.isDebit), style: t.amountRow),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: c.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          line(credit),
          line(debit),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    dayMonth(credit.occurredAt),
                    left > 0 ? '${inr(left)} left counts' : 'cancels in full',
                  ].join(' · '),
                  style: t.meta,
                ),
              ),
              TextButton(
                onPressed: () =>
                    getIt<OffsetLinker>().dismiss([credit.id, debit.id]),
                child: const Text('No'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                icon: const Icon(Symbols.link, size: 20),
                label: const Text('Cancels out'),
                onPressed: () =>
                    getIt<OffsetLinker>().link(credit.id, debit.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
