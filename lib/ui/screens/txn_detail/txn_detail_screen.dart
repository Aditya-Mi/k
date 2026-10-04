import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/db/app_database.dart' hide ParserTemplate, SenderRule;
import '../../../data/db/enums.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/ingest/transfer_linker.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import '../../widgets/raw_message_card.dart';
import '../../widgets/rosette.dart';
import '../../widgets/text_prompt.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../subscriptions/subscription_detail_screen.dart';
import '../subscriptions/track_subscription_sheet.dart';

class TxnDetailState {
  const TxnDetailState({
    this.detail,
    this.categories = const [],
    this.loaded = false,
  });

  final TxnDetailView? detail;
  final List<Category> categories;
  final bool loaded;
}

class TxnDetailCubit extends Cubit<TxnDetailState> {
  TxnDetailCubit(this._ledger, this._transfers, this.txnId)
    : super(const TxnDetailState()) {
    _subs
      ..add(
        _ledger
            .watchDetail(txnId)
            .listen(
              (d) => _safeEmit(
                TxnDetailState(
                  detail: d,
                  categories: state.categories,
                  loaded: true,
                ),
              ),
            ),
      )
      ..add(
        _ledger.watchCategories().listen(
          (c) => _safeEmit(
            TxnDetailState(
              detail: state.detail,
              categories: c,
              loaded: state.loaded,
            ),
          ),
        ),
      );
  }

  final LedgerRepository _ledger;
  final TransferLinker _transfers;
  final String txnId;
  final _subs = <StreamSubscription<Object?>>[];

  void _safeEmit(TxnDetailState s) {
    if (!isClosed) emit(s);
  }

  Future<void> setCategory(String id, {bool forMerchant = false}) =>
      _ledger.setCategory(txnId, id, applyToMerchant: forMerchant);
  Future<void> renamePayee(String merchantId, String name) =>
      _ledger.renameMerchant(merchantId, name);
  Future<void> unlinkTransfer() => _transfers.unlink(txnId);
  Future<void> markTransfer({String? partnerId, String? addOnAccountId}) =>
      _transfers.markManual(
        txnId,
        partnerId: partnerId,
        addOnAccountId: addOnAccountId,
      );
  Future<List<Transaction>> transferCandidates() =>
      _transfers.candidatesFor(txnId);
  Future<List<AccountView>> accounts() => _ledger.watchAccounts().first;
  Future<void> setNote(String? note) => _ledger.setNote(txnId, note);
  Future<void> remove({required bool notATransaction}) =>
      _ledger.removeTransaction(txnId, notATransaction: notATransaction);

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}

class TxnDetailScreen extends StatelessWidget {
  const TxnDetailScreen({super.key, required this.txnId});

  final String txnId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => TxnDetailCubit(
      getIt<LedgerRepository>(),
      getIt<TransferLinker>(),
      txnId,
    ),
    child: const _DetailView(),
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TxnDetailCubit, TxnDetailState>(
      builder: (context, s) {
        final d = s.detail;
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: s.loaded
                ? const Center(
                    child: EmptyState(title: 'This transaction was removed'),
                  )
                : const SizedBox.shrink(),
          );
        }
        return _Loaded(detail: d, categories: s.categories);
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.detail, required this.categories});

  final TxnDetailView detail;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final txn = detail.txn;
    final band = Bands.of(txn.amountMinor);
    final cubit = context.read<TxnDetailCubit>();
    final sources = detail.sources;

    return Scaffold(
      body: Stack(
        children: [
          // Watermark: house rosette in this amount's ink, 40%, top-right.
          Positioned(
            top: MediaQuery.paddingOf(context).top + 24,
            right: -24,
            child: Opacity(
              opacity: 0.4,
              child: Rosette(size: 118, color: c.ink(band), strokeWidth: 0.6),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.list(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        LargeNoteChip(
                          amountMinor: txn.amountMinor,
                          outlined: !txn.isDebit,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              inr(
                                txn.amountMinor,
                                paise: true,
                                plus: !txn.isDebit,
                              ),
                              style: t.amountHero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: txn.merchantId == null || txn.isTransfer
                          ? null
                          : () => _renamePayee(context, cubit, txn),
                      child: Row(
                        children: [
                          Flexible(child: Text(txn.payee, style: t.headline)),
                          if (txn.merchantId != null && !txn.isTransfer) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.edit_outlined, size: 18, color: c.text3),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${txn.isDebit ? 'Debit' : 'Credit'} · '
                      '${fullStamp(txn.occurredAt)} · '
                      '${txn.isTransfer
                          ? 'not counted as spent'
                          : txn.isCash
                          ? 'from cash, counted at the ATM'
                          : '${Bands.ranges[band]} range'}',
                      style: t.body.copyWith(color: c.text2),
                    ),
                    const SizedBox(height: 24),
                    FieldRow(
                      label: 'Category',
                      value: CategoryButton(
                        category: txn.category,
                        onTap: () => _pickCategory(context, cubit, txn),
                      ),
                    ),
                    if (txn.account != null)
                      FieldRow(
                        label: 'Account',
                        value: Text(
                          txn.account!.long,
                          style: t.body,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    FieldRow(
                      label: txn.isDebit ? 'Paid by' : 'Came by',
                      value: Text(_typeLabel(txn.txnType), style: t.body),
                    ),
                    if (txn.balanceMinor != null)
                      FieldRow(
                        label: txn.account?.type == AccountType.creditCard
                            ? 'Available limit'
                            : 'Balance after',
                        value: Text(
                          inr(txn.balanceMinor!, paise: true),
                          style: t.amountRow.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (txn.refNo != null)
                      FieldRow(
                        label: 'Reference',
                        value: SelectableText(txn.refNo!, style: t.body),
                      ),
                    if (txn.isTransfer)
                      FieldRow(
                        label: 'Self transfer',
                        value: Text(
                          txn.transferRoute,
                          style: t.body,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    if (txn.subscriptionId != null)
                      _SubscriptionField(id: txn.subscriptionId!),
                    FieldRow(
                      label: 'Note',
                      onTap: () => _editNote(context, cubit, txn.notes),
                      value: Text(
                        txn.notes ?? 'Add a note',
                        style: t.body.copyWith(
                          color: txn.notes == null ? c.text3 : c.text,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      txn.addedByUser
                          ? 'Added by you'
                          : sources.length > 1
                          ? 'Came from ${sources.length} bank messages'
                          : 'Came from this bank message',
                      style: t.title.copyWith(fontSize: 18),
                    ),
                    if (txn.addedByUser) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail.sourcesFromPartner
                            ? 'Your bank sent no message for this side. It '
                                  'mirrors the other side of the transfer:'
                            : 'Your bank sent no message for this.',
                        style: t.body.copyWith(color: c.text2),
                      ),
                    ] else if (sources.length > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Same amount, account and time, so they were merged into one',
                        style: t.body.copyWith(color: c.text2),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (final (i, m) in sources.indexed) ...[
                      RawMessageCard(
                        message: m,
                        merged: i > 0 && !detail.sourcesFromPartner,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (txn.isDebit &&
                            !txn.isTransfer &&
                            txn.merchantId != null &&
                            txn.subscriptionId == null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.autorenew_rounded, size: 20),
                            label: const Text('Track as subscription'),
                            onPressed: () =>
                                showTrackSubscriptionSheet(context, txn),
                          ),
                        if (txn.isTransfer)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.link_off_rounded, size: 20),
                            label: const Text('Not a self transfer'),
                            onPressed: cubit.unlinkTransfer,
                          )
                        else if (!txn.isCash)
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 20,
                            ),
                            label: const Text('Mark as self transfer'),
                            onPressed: () => _markTransfer(context, cubit, txn),
                          ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.block_rounded, size: 20),
                          label: const Text('Not a transaction'),
                          onPressed: () =>
                              _remove(context, cubit, notATransaction: true),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                          label: const Text('Delete'),
                          onPressed: () =>
                              _remove(context, cubit, notATransaction: false),
                        ),
                      ],
                    ),
                    SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(TxnType type) => switch (type) {
    TxnType.upi => 'UPI',
    TxnType.card => 'Card',
    TxnType.neft => 'NEFT',
    TxnType.imps => 'IMPS',
    TxnType.rtgs => 'RTGS',
    TxnType.atm => 'ATM',
    TxnType.autopay => 'AutoPay',
    TxnType.netBanking => 'Net banking',
    TxnType.other => 'Other',
  };

  Future<void> _pickCategory(
    BuildContext context,
    TxnDetailCubit cubit,
    TxnView txn,
  ) async {
    // Teach the merchant by default; transfers and payee-less rows can't.
    var forMerchant = txn.merchantId != null && !txn.isTransfer;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (txn.merchantId != null && !txn.isTransfer)
                  SwitchListTile(
                    value: forMerchant,
                    onChanged: (v) => setSheet(() => forMerchant = v),
                    title: Text('Use for all ${txn.payee}'),
                    subtitle: const Text(
                      'Past and future payments, unless you set one yourself',
                    ),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final cat in categories)
                        ListTile(
                          leading: Icon(
                            categoryIcon(cat.icon),
                            color: context.k.text2,
                          ),
                          title: Text(cat.name),
                          trailing: cat.id == txn.category?.id
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, cat.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null && (picked != txn.category?.id || forMerchant)) {
      await cubit.setCategory(picked, forMerchant: forMerchant);
    }
  }

  Future<void> _renamePayee(
    BuildContext context,
    TxnDetailCubit cubit,
    TxnView txn,
  ) async {
    final name = await promptText(
      context,
      title: 'Rename payee',
      initial: txn.payee,
      help: 'Changes every payment to them.',
    );
    if (name != null && name.trim().isNotEmpty) {
      await cubit.renamePayee(txn.merchantId!, name);
    }
  }

  /// Other side of the transfer: a same-amount row on another account, or
  /// "not in k" when that account is not tracked.
  Future<void> _markTransfer(
    BuildContext context,
    TxnDetailCubit cubit,
    TxnView txn,
  ) async {
    final candidates = await cubit.transferCandidates();
    final accounts = {for (final a in await cubit.accounts()) a.id: a};
    if (!context.mounted) return;
    final t = context.kt;
    // Own accounts with no matching row: the other side can be added there.
    final withRow = {for (final o in candidates) o.accountId};
    final addable = accounts.values
        .where(
          (a) =>
              a.id != txn.account?.id && !a.isCash && !withRow.contains(a.id),
        )
        .toList();
    final picked = await showModalBottomSheet<({String? partner, String? addOn})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  txn.isDebit ? 'Where did it go?' : 'Where did it come from?',
                  style: t.title,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  candidates.isEmpty
                      ? 'No ${inrRow(txn.amountMinor)} '
                            '${txn.isDebit ? 'credit' : 'debit'} on another '
                            'account within 3 days.'
                      : 'Same amount on your other accounts, within 3 days.',
                  style: t.meta,
                ),
              ),
              for (final o in candidates)
                ListTile(
                  leading: NoteChip(
                    amountMinor: o.amountMinor,
                    style: o.direction == Direction.debit
                        ? NoteChipStyle.filled
                        : NoteChipStyle.outlined,
                  ),
                  title: Text(
                    accounts[o.accountId]?.short ?? 'Unknown account',
                  ),
                  subtitle: Text(
                    [
                      ?o.payeeRaw,
                      '${dayMonth(o.occurredAt)}, ${hhmm(o.occurredAt)}',
                    ].join(' · '),
                  ),
                  onTap: () =>
                      Navigator.pop(context, (partner: o.id, addOn: null)),
                ),
              for (final a in addable)
                ListTile(
                  leading: Icon(Icons.add_rounded, color: context.k.text2),
                  title: Text('${txn.isDebit ? 'To' : 'From'} ${a.short}'),
                  subtitle: const Text('No message from this bank — add it'),
                  onTap: () =>
                      Navigator.pop(context, (partner: null, addOn: a.id)),
                ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(
                  txn.isDebit
                      ? 'To an account not in k'
                      : 'From an account not in k',
                ),
                onTap: () =>
                    Navigator.pop(context, (partner: null, addOn: null)),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await cubit.markTransfer(
        partnerId: picked.partner,
        addOnAccountId: picked.addOn,
      );
    }
  }

  Future<void> _editNote(
    BuildContext context,
    TxnDetailCubit cubit,
    String? current,
  ) async {
    final note = await promptText(
      context,
      title: 'Note',
      initial: current ?? '',
      hint: 'Add a note',
      maxLines: 3,
    );
    if (note != null) await cubit.setNote(note);
  }

  Future<void> _remove(
    BuildContext context,
    TxnDetailCubit cubit, {
    required bool notATransaction,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          notATransaction ? 'Not a transaction?' : 'Delete transaction?',
        ),
        content: Text(
          notATransaction
              ? 'It leaves the ledger. The bank message is kept and marked, '
                    'so it will not be logged again.'
              : 'It leaves the ledger. The bank message is kept for the record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(notATransaction ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await cubit.remove(notATransaction: notATransaction);
    if (context.mounted) Navigator.pop(context);
  }
}

/// "Subscription · Apple Media Services ›" — opens the plan.
class _SubscriptionField extends StatelessWidget {
  const _SubscriptionField({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return StreamBuilder<SubscriptionView?>(
      stream: getIt<SubscriptionService>().watchOne(id),
      builder: (context, snap) {
        final sub = snap.data;
        if (sub == null) return const SizedBox.shrink();
        return FieldRow(
          label: 'Subscription',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SubscriptionDetailScreen(id: id),
            ),
          ),
          value: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  sub.name,
                  style: t.body,
                  textAlign: TextAlign.right,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.k.text2),
            ],
          ),
        );
      },
    );
  }
}
