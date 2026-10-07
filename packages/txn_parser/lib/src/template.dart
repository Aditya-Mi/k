import 'package:meta/meta.dart';

import 'enums.dart';

/// Named groups a template may capture. Anything else is ignored.
abstract final class Fields {
  static const amount = 'amount';
  static const direction = 'direction';
  static const type = 'type';
  static const last4 = 'last4';

  /// Debit card last 4, when the alert names the card as well as the account.
  static const card = 'card';
  static const payee = 'payee';
  static const ref = 'ref';
  static const date = 'date';
  static const balance = 'balance';
  static const dueDate = 'dueDate';
  static const mandateRef = 'mandateRef';
  static const currency = 'currency';

  static const all = [
    amount, direction, type, last4, card, payee, ref, date, balance, //
    dueDate, mandateRef, currency,
  ];
}

/// One regex per bank/message format. Matched against whitespace-normalized
/// text (see normalizeText), case-insensitively.
@immutable
class ParserTemplate {
  ParserTemplate({
    required this.id,
    required this.bankCode,
    required this.channel,
    required this.pattern,
    this.kind = TemplateKind.transaction,
    this.name = '',
    this.defaults = const {},
    this.priority = 100,
  }) : regex = RegExp(pattern, caseSensitive: false);

  final String id;
  final String bankCode;
  final Channel channel;
  final TemplateKind kind;
  final String name;
  final String pattern;
  final RegExp regex;

  /// Fixed values for fields the regex does not capture,
  /// e.g. {'direction': 'debit', 'txnType': 'card'}.
  final Map<String, String> defaults;

  /// Lower runs first. User templates use < 100 to beat built-ins.
  final int priority;
}

/// Shorthands for built-in template patterns. Only for hand-written
/// templates — generated ones are already expanded.
String rx(String pattern) => pattern
    .replaceAll('{amt}', r'[\d,]+(?:\.\d{1,2})?')
    .replaceAll('{rs}', r'(?:INR|Rs\.?|₹)\s?');
