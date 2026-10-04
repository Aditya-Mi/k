import 'package:equatable/equatable.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart';
import '../db/enums.dart';

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
  });

  final String id;
  final String bankId;
  final String bankName;
  final AccountType type;
  final String? last4;
  final String? nickname;

  bool get isCard =>
      type == AccountType.creditCard || type == AccountType.debitCard;

  String get _digits => last4 == null ? '' : ' ··$last4';

  /// Row meta: "Axis ··1234", "Axis card ··5678".
  String get short =>
      nickname ??
      '${bankShortName(bankId, bankName)}${isCard ? ' card' : ''}$_digits';

  /// Detail: "Axis Bank credit card ··5678".
  String get long {
    if (nickname != null) return nickname!;
    final kind = switch (type) {
      AccountType.creditCard => ' credit card',
      AccountType.debitCard => ' debit card',
      AccountType.current => ' current a/c',
      AccountType.wallet => ' wallet',
      _ => '',
    };
    return '$bankName$kind$_digits';
  }

  @override
  List<Object?> get props => [id, bankId, bankName, type, last4, nickname];
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
    this.transferPartnerId,
    this.partnerAccount,
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

  bool get isTransfer => transferId != null;

  /// "Axis ··0640 → Kotak ··4410"; an untracked side reads "own account".
  String get transferRoute {
    const other = 'own account';
    final mine = account?.short ?? 'this account';
    final theirs = partnerAccount?.short ?? other;
    return isDebit ? '$mine → $theirs' : '$theirs → $mine';
  }

  bool get isDebit => direction == Direction.debit;
  bool get merged => sourceCount > 1;

  @override
  List<Object?> get props => [
    id, amountMinor, currency, direction, txnType, occurredAt, payee, //
    sourceCount, account, category, balanceMinor, notes, refNo, transferId,
    transferPartnerId, partnerAccount,
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
  const TxnDetailView(this.txn, this.sources);

  final TxnView txn;

  /// Bank messages behind this transaction, oldest first.
  final List<RawMessage> sources;

  @override
  List<Object?> get props => [txn, sources];
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
