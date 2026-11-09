import 'package:equatable/equatable.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import '../ingest/category_resolver.dart';

/// "Axis Bank" → "Axis", "Kotak Mahindra Bank" → "Kotak", "Bank of Baroda" → "BOB".
String bankShortName(String bankId, String bankName) => switch (bankId) {
  'AXIS' => 'Axis',
  'KOTAK' => 'Kotak',
  'BOB' => 'BOB',
  _ =>
    bankName
        .replaceAll(RegExp(r'\s*Bank\s*', caseSensitive: false), ' ')
        .trim(),
};

class AccountView extends Equatable {
  const AccountView({
    required this.id,
    required this.bankId,
    required this.bankName,
    required this.type,
    this.last4,
    this.nickname,
    this.includes = const [],
    this.creditLimitMinor,
  });

  final String id;
  final String bankId;
  final String bankName;
  final AccountType type;
  final String? last4;
  final String? nickname;

  /// Accounts folded into this one, e.g. "card ··4444".
  final List<String> includes;

  /// Credit card: total limit the owner entered.
  final int? creditLimitMinor;

  bool get isCreditCard => type == AccountType.creditCard;

  /// Credit card owed: limit minus [availableMinor], never below 0.
  int? owedMinor(int? availableMinor) {
    final limit = creditLimitMinor;
    if (limit == null || availableMinor == null) return null;
    final owed = limit - availableMinor;
    return owed < 0 ? 0 : owed;
  }

  bool get isCard =>
      type == AccountType.creditCard || type == AccountType.debitCard;

  bool get isCash => type == AccountType.cash;

  String get _digits => last4 == null ? '' : ' ··$last4';

  /// Row meta, where width is short: "Axis ··1234", "Axis card ··5678".
  String get short =>
      nickname ??
      (isCash ? 'Cash' : null) ??
      '${bankShortName(bankId, bankName)}${isCard ? ' card' : ''}$_digits';

  /// The account's name everywhere else (detail, Accounts, card screen):
  /// "Axis ··1234", "Axis credit card ··5678". A nickname wins.
  String get long {
    if (nickname != null) return nickname!;
    if (isCash) return 'Cash in hand';
    final kind = switch (type) {
      AccountType.creditCard => ' credit card',
      AccountType.debitCard => ' debit card',
      AccountType.current => ' current a/c',
      AccountType.wallet => ' wallet',
      _ => '',
    };
    return '${bankShortName(bankId, bankName)}$kind$_digits';
  }

  @override
  List<Object?> get props => [
    id, bankId, bankName, type, last4, nickname, includes, //
    creditLimitMinor,
  ];
}

class TxnView extends Equatable {
  const TxnView({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.direction,
    required this.txnType,
    required this.occurredAt,
    required this.payee,
    required this.sourceCount,
    this.account,
    this.category,
    this.balanceMinor,
    this.notes,
    this.refNo,
    this.transferId,
    this.merchantId,
    this.origin = TxnOrigin.message,
    this.transferPartnerId,
    this.partnerAccount,
    this.subscriptionId,
    this.emi,
    this.splits = const [],
    this.offsetId,
    this.offsetCancelledMinor = 0,
    this.offsetOthers = 0,
  });

  final String id;
  final int amountMinor;
  final String currency;
  final Direction direction;
  final TxnType txnType;
  final DateTime occurredAt;

  /// Merchant display name, else the raw payee, else a fallback.
  final String payee;
  final int sourceCount;
  final AccountView? account;
  final Category? category;
  final int? balanceMinor;
  final String? notes;
  final String? refNo;

  /// Set when this is one side of a self transfer.
  final String? transferId;

  /// The other side, when that account is tracked.
  final String? transferPartnerId;
  final AccountView? partnerAccount;

  final TxnOrigin origin;
  final String? merchantId;

  /// Matched to a subscription (one of its charges).
  final String? subscriptionId;

  /// The EMI this is the purchase or an instalment of.
  final EmiLink? emi;

  /// Parts filed under other categories; the rest stays in [category].
  final List<SplitPart> splits;

  /// Cancels out with other payments (money passed on, paid back, a failed
  /// payment reversed): they share this id.
  final String? offsetId;

  /// How much of this payment nets against the others in its group.
  final int offsetCancelledMinor;

  /// How many payments it cancels out with.
  final int offsetOthers;

  bool get isSplit => splits.isNotEmpty;

  bool get hasOffset => offsetId != null;

  /// What still counts after cancelling out.
  int get countedMinor => amountMinor - offsetCancelledMinor;

  /// Cancels out in full: counts nowhere.
  bool get cancelsOut => hasOffset && countedMinor <= 0;

  TxnView withSplits(List<SplitPart> parts) => _copy(splits: parts);

  TxnView withOffset(
    ({String offsetId, int cancelledMinor, int others})? share,
  ) => share == null
      ? this
      : _copy(
          offsetId: share.offsetId,
          offsetCancelledMinor: share.cancelledMinor,
          offsetOthers: share.others,
        );

  TxnView _copy({
    List<SplitPart>? splits,
    String? offsetId,
    int? offsetCancelledMinor,
    int? offsetOthers,
  }) => TxnView(
    id: id,
    amountMinor: amountMinor,
    currency: currency,
    direction: direction,
    txnType: txnType,
    occurredAt: occurredAt,
    payee: payee,
    sourceCount: sourceCount,
    account: account,
    category: category,
    balanceMinor: balanceMinor,
    notes: notes,
    refNo: refNo,
    transferId: transferId,
    merchantId: merchantId,
    origin: origin,
    transferPartnerId: transferPartnerId,
    partnerAccount: partnerAccount,
    subscriptionId: subscriptionId,
    emi: emi,
    splits: splits ?? this.splits,
    offsetId: offsetId ?? this.offsetId,
    offsetCancelledMinor: offsetCancelledMinor ?? this.offsetCancelledMinor,
    offsetOthers: offsetOthers ?? this.offsetOthers,
  );

  /// What's left in [category] after the split parts (never below 0).
  int get restMinor {
    final rest = amountMinor - splits.fold<int>(0, (s, p) => s + p.amountMinor);
    return rest < 0 ? 0 : rest;
  }

  /// (category, amount) pieces adding up to the payment: the rest first,
  /// then each split part. One piece when not split.
  List<(Category?, int)> get pieces => [
    if (!isSplit || restMinor > 0)
      (category, isSplit ? restMinor : amountMinor),
    for (final p in splits) (p.category, p.amountMinor),
  ];

  bool get isTransfer => transferId != null;

  /// A self transfer to or from a credit card: paying its bill.
  bool get isCardBill => isTransfer && category?.id == 'cat_card_bill';

  /// Money back that lowers spent instead of coming in: a credit filed
  /// under a spending category (a refund lands in the month it arrives), or
  /// any money back on a credit card that isn't filed as income or neither.
  bool get isRefund {
    if (isDebit || isTransfer) return false;
    final kind = category?.kind;
    if (kind == CategoryKind.neutral || kind == CategoryKind.income) {
      return false;
    }
    if (account?.type == AccountType.creditCard) return true;
    return kind == CategoryKind.spend && category!.id != uncategorizedId;
  }

  /// Filed under a category that counts as neither spent nor came in
  /// (investments, deposits, loans).
  bool get isNeutral => !isSplit && category?.kind == CategoryKind.neutral;

  /// Left out of totals because of an EMI: a spread purchase (its
  /// instalments count instead), or a card instalment of a purchase that
  /// already counted once.
  bool get _emiExcluded {
    final e = emi;
    if (e == null) return false;
    if (e.isPurchase) return e.spread;
    return e.kind == EmiKind.card && !e.spread;
  }

  /// Paid from (or into) cash in hand.
  bool get isCash => account?.isCash ?? false;

  /// Bank → cash in hand: parsed as ATM, or filed under ATM withdrawal.
  /// Like a self transfer, the money is still the owner's until spent.
  bool get isAtmWithdrawal =>
      !isCash &&
      isDebit &&
      (txnType == TxnType.atm || category?.id == atmCategoryId);

  /// Counts toward spent / came in. Self transfers and ATM withdrawals
  /// don't (cash counts when it's spent); see also [_emiExcluded].
  /// Nor do payments filed as neither, or ones that cancel out in full.
  bool get countsInTotals =>
      !isTransfer &&
      !isAtmWithdrawal &&
      !_emiExcluded &&
      !isNeutral &&
      !cancelsOut;

  /// [pieces] as they count: what cancels out comes off the rest first,
  /// then off split parts in order; parts filed as neither drop out.
  List<(Category?, int)> get countedPieces {
    var cut = offsetCancelledMinor;
    final out = <(Category?, int)>[];
    for (final (cat, amount) in pieces) {
      final take = cut < amount ? cut : amount;
      cut -= take;
      final left = amount - take;
      if (left > 0 && cat?.kind != CategoryKind.neutral) out.add((cat, left));
    }
    return out;
  }

  int get _counted => countedPieces.fold(0, (s, p) => s + p.$2);

  /// Signed contribution to spent: debits add, refunds subtract.
  int get spentMinor => !countsInTotals
      ? 0
      : isDebit
      ? _counted
      : isRefund
      ? -_counted
      : 0;

  /// Contribution to came in (refunds lower spent instead).
  int get inMinor => countsInTotals && !isDebit && !isRefund ? _counted : 0;
  bool get addedByUser => origin == TxnOrigin.user;

  /// "Axis ··1111 → Kotak ··5555"; an untracked side reads "own account".
  String get transferRoute {
    final other = isCardBill ? 'credit card' : 'own account';
    final mine = account?.short ?? 'this account';
    final theirs = partnerAccount?.short ?? other;
    return isDebit ? '$mine → $theirs' : '$theirs → $mine';
  }

  bool get isDebit => direction == Direction.debit;
  bool get merged => sourceCount > 1;

  @override
  List<Object?> get props => [
    id, amountMinor, currency, direction, txnType, occurredAt, payee, //
    sourceCount,
    account,
    category,
    balanceMinor,
    notes,
    refNo,
    transferId,
    merchantId,
    origin,
    transferPartnerId, partnerAccount, subscriptionId, emi, splits,
    offsetId, offsetCancelledMinor, offsetOthers,
  ];
}

/// One part of a split payment.
class SplitPart extends Equatable {
  const SplitPart({
    required this.id,
    required this.category,
    required this.amountMinor,
  });

  final String id;
  final Category category;
  final int amountMinor;

  @override
  List<Object?> get props => [id, category, amountMinor];
}

/// Categories as a one-level tree: each top-level category followed by
/// the ones inside it, both in sort order. A child whose parent is gone or
/// not in [all] shows as top-level.
List<(Category, int)> categoryTree(List<Category> all) {
  final ids = {for (final c in all) c.id};
  bool top(Category c) => c.parentId == null || !ids.contains(c.parentId);
  return [
    for (final p in all.where(top)) ...[
      (p, 0),
      for (final c in all)
        if (!top(c) && c.parentId == p.id) (c, 1),
    ],
  ];
}

/// Categories that hold payments of their own only: k's structural ones
/// can't go inside another or hold sub-categories.
const structuralCategoryIds = {
  'cat_transfers',
  'cat_card_bill',
  'cat_cash',
  'cat_income',
  'cat_uncategorized',
};

/// What a transaction is to its EMI.
class EmiLink extends Equatable {
  const EmiLink({
    required this.id,
    required this.name,
    required this.kind,
    required this.isPurchase,
    required this.spread,
    required this.count,
    required this.amountMinor,
  });

  final String id;
  final String name;
  final EmiKind kind;

  /// The purchase converted to EMI (else one instalment).
  final bool isPurchase;
  final bool spread;
  final int count;
  final int amountMinor;

  @override
  List<Object?> get props => [
    id, name, kind, isPurchase, spread, count, amountMinor, //
  ];
}

class UpcomingView extends Equatable {
  const UpcomingView({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.dueDate,
    this.bankShort,
  });

  final String id;
  final String name;
  final int amountMinor;
  final DateTime dueDate;
  final String? bankShort;

  @override
  List<Object?> get props => [id, name, amountMinor, dueDate, bankShort];
}

class TxnDetailView extends Equatable {
  const TxnDetailView(
    this.txn,
    this.sources, {
    this.sourcesFromPartner = false,
  });

  final TxnView txn;

  /// Bank messages behind this transaction, oldest first.
  final List<RawMessage> sources;

  /// True when [txn] was added by the owner and [sources] are the messages of
  /// the other side of its self transfer.
  final bool sourcesFromPartner;

  @override
  List<Object?> get props => [txn, sources, sourcesFromPartner];
}

enum BalanceSource { bank, manual }

class AccountBalance extends Equatable {
  const AccountBalance({
    required this.amountMinor,
    required this.asOf,
    required this.source,
    required this.anchorAt,
    this.estimatedFrom = 0,
  });

  /// Balance, or available limit for a credit card.
  final int amountMinor;

  /// Time of the newest money movement included.
  final DateTime asOf;

  /// Where the last known figure came from, and when.
  final BalanceSource source;
  final DateTime anchorAt;

  /// Payments after that figure, added or subtracted by k. 0 = exact.
  final int estimatedFrom;

  bool get estimated => estimatedFrom > 0;

  @override
  List<Object?> get props => [
    amountMinor,
    asOf,
    source,
    anchorAt,
    estimatedFrom,
  ];
}

/// Last known figure — the newest bank-reported balance on a transaction, or
/// the owner's manual entry if that is newer — plus every later movement
/// (credits add, debits subtract; same for a card's available limit).
/// Null when nothing is known yet.
AccountBalance? computeBalance(Account account, List<Transaction> txns) {
  Transaction? reported;
  for (final t in txns) {
    if (t.balanceMinor == null) continue;
    if (reported == null || _laterReport(t, reported)) reported = t;
  }
  int base;
  DateTime anchor;
  BalanceSource source;
  final manualAt = account.manualBalanceAt;
  if (account.manualBalanceMinor != null &&
      manualAt != null &&
      (reported == null || !manualAt.isBefore(reported.occurredAt))) {
    base = account.manualBalanceMinor!;
    anchor = manualAt;
    source = BalanceSource.manual;
  } else if (reported != null) {
    base = reported.balanceMinor!;
    anchor = reported.occurredAt;
    source = BalanceSource.bank;
  } else {
    return null;
  }
  var asOf = anchor;
  var moved = 0;
  for (final t in txns) {
    if (!t.occurredAt.isAfter(anchor)) continue;
    base += t.direction == Direction.credit ? t.amountMinor : -t.amountMinor;
    moved++;
    if (t.occurredAt.isAfter(asOf)) asOf = t.occurredAt;
  }
  return AccountBalance(
    amountMinor: base,
    asOf: asOf,
    source: source,
    anchorAt: anchor,
    estimatedFrom: moved,
  );
}

/// Bank times are to the minute: of two alerts in the same minute, the one
/// that arrived later (then the later id, UUIDv7) carries the newer balance.
bool _laterReport(Transaction a, Transaction b) {
  final c = a.occurredAt.compareTo(b.occurredAt);
  if (c != 0) return c > 0;
  final d = a.createdAt.compareTo(b.createdAt);
  if (d != 0) return d > 0;
  return a.id.compareTo(b.id) > 0;
}

/// Cash in hand: the owner's figure (or 0 before one) plus ATM withdrawals
/// from any account and cash received, minus cash payments, after it.
AccountBalance? computeCashBalance(
  Account cash,
  List<Transaction> cashTxns,
  List<Transaction> atmWithdrawals,
) {
  if (cashTxns.isEmpty &&
      atmWithdrawals.isEmpty &&
      cash.manualBalanceMinor == null) {
    return null;
  }
  final manual =
      cash.manualBalanceAt != null && cash.manualBalanceMinor != null;
  final anchor = manual
      ? cash.manualBalanceAt!
      : DateTime.fromMillisecondsSinceEpoch(0);
  var base = manual ? cash.manualBalanceMinor! : 0;
  var asOf = anchor;
  var moved = 0;
  void add(Transaction t, int signed) {
    if (!t.occurredAt.isAfter(anchor)) return;
    base += signed;
    moved++;
    if (t.occurredAt.isAfter(asOf)) asOf = t.occurredAt;
  }

  for (final t in atmWithdrawals) {
    add(t, t.direction == Direction.debit ? t.amountMinor : -t.amountMinor);
  }
  for (final t in cashTxns) {
    add(t, t.direction == Direction.credit ? t.amountMinor : -t.amountMinor);
  }
  return AccountBalance(
    amountMinor: base,
    asOf: asOf,
    source: BalanceSource.manual,
    anchorAt: anchor,
    estimatedFrom: moved,
  );
}

/// List filter. [from]/[to] is a half-open range on occurredAt.
class TxnFilter extends Equatable {
  const TxnFilter({
    required this.from,
    required this.to,
    this.accountIds = const {},
    this.categoryIds = const {},
    this.direction,
    this.query = '',
  });

  factory TxnFilter.month(DateTime month) => TxnFilter(
    from: DateTime(month.year, month.month),
    to: DateTime(month.year, month.month + 1),
  );

  final DateTime from;
  final DateTime to;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Direction? direction;
  final String query;

  TxnFilter copyWith({
    DateTime? from,
    DateTime? to,
    Set<String>? accountIds,
    Set<String>? categoryIds,
    Direction? Function()? direction,
    String? query,
  }) => TxnFilter(
    from: from ?? this.from,
    to: to ?? this.to,
    accountIds: accountIds ?? this.accountIds,
    categoryIds: categoryIds ?? this.categoryIds,
    direction: direction != null ? direction() : this.direction,
    query: query ?? this.query,
  );

  /// Only the period — what the month panel summarises.
  TxnFilter get periodOnly => TxnFilter(from: from, to: to);

  @override
  List<Object?> get props => [
    from, to, accountIds.toList()..sort(), categoryIds.toList()..sort(), //
    direction, query,
  ];
}
