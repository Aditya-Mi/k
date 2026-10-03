import 'package:meta/meta.dart';

import 'enums.dart';

enum ParseStatus {
  /// Template matched and all required fields present.
  parsed,

  /// Bank message, but fields incomplete — goes to the review queue.
  needsReview,

  /// Bank message that is not a transaction (OTP, promo, declined).
  nonTransaction,

  /// Sender is not a configured bank — drop, do not store.
  notBank,
}

@immutable
class ParsedFields {
  const ParsedFields({
    this.amountMinor,
    this.currency = 'INR',
    this.direction,
    this.txnType,
    this.last4,
    this.payee,
    this.ref,
    this.occurredAt,
    this.balanceMinor,
    this.dueDate,
    this.mandateRef,
  });

  final int? amountMinor;
  final String currency;
  final Direction? direction;
  final TxnType? txnType;
  final String? last4;
  final String? payee;
  final String? ref;
  final DateTime? occurredAt;

  /// Account balance, or available limit for credit cards.
  final int? balanceMinor;

  /// Mandate alerts only: when the charge will hit.
  final DateTime? dueDate;
  final String? mandateRef;

  Map<String, Object?> toMap() => {
    'amountMinor': amountMinor,
    'currency': currency,
    'direction': direction?.name,
    'txnType': txnType?.name,
    'last4': last4,
    'payee': payee,
    'ref': ref,
    'occurredAt': occurredAt?.toIso8601String(),
    'balanceMinor': balanceMinor,
    'dueDate': dueDate?.toIso8601String(),
    'mandateRef': mandateRef,
  };

  @override
  String toString() => 'ParsedFields${toMap()}';
}

@immutable
class ParseResult {
  const ParseResult({
    required this.status,
    this.bankCode,
    this.kind = TemplateKind.transaction,
    this.templateId,
    this.fields = const ParsedFields(),
    this.missing = const [],
    this.note,
  });

  final ParseStatus status;
  final String? bankCode;
  final TemplateKind kind;
  final String? templateId;
  final ParsedFields fields;

  /// Required fields that could not be extracted.
  final List<String> missing;

  /// Why it ended in this status (prefilter reason, fallback, ...).
  final String? note;

  @override
  String toString() =>
      'ParseResult($status, bank: $bankCode, kind: ${kind.name}, '
      'template: $templateId, missing: $missing, note: $note, $fields)';
}
