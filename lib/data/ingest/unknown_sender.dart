import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart' hide ParserTemplate, SenderRule;

/// "JD-HDFCBK-S" → "HDFCBK", "VM-HDFCBK" → "HDFCBK", "HDFCBK" → "HDFCBK".
/// The core is what a sender rule matches, so one rule covers every
/// operator prefix and -S/-T/-P suffix the bank sends with.
String senderCore(String sender) {
  final parts = sender.trim().toUpperCase().split('-');
  if (parts.length > 1 && parts.first.length == 2) parts.removeAt(0);
  if (parts.length > 1 && parts.last.length == 1) parts.removeLast();
  return parts.join('-');
}

/// Business SMS headers carry letters; personal numbers never reach review.
bool isBusinessSender(String sender) =>
    RegExp('[A-Za-z]').hasMatch(senderCore(sender));

final _moneyWords = RegExp(
  r'\b(debited|credited|spent|withdrawn|deposited|sent|received|txn'
  r'|transaction|a/?c|acct|upi|neft|imps|rtgs)\b',
  caseSensitive: false,
);

/// An SMS from a sender no bank rule knows, read as if it came from a bank.
/// Worth reviewing when it carries an amount and payment wording and is not
/// an OTP, promo or decline (the parser's own prefilters decide that).
ParseResult? probeUnknown(RawInput input) {
  if (input.channel != Channel.sms || !isBusinessSender(input.sender)) {
    return null;
  }
  final result = ParserEngine(
    banks: const [],
    senderRules: [SenderRule(unknownBankCode, Channel.sms, input.sender)],
  ).parse(input);
  if (result.status != ParseStatus.needsReview) return null;
  if (result.fields.amountMinor == null) return null;
  final text = normalizeText([?input.subject, input.body].join(' '));
  if (!_moneyWords.hasMatch(text)) return null;
  return ParseResult(
    status: ParseStatus.needsReview,
    fields: result.fields,
    missing: const ['sender'],
    note: unknownSenderNote,
  );
}

/// Placeholder bank code for probing only; never stored.
const unknownBankCode = '?';
const unknownSenderNote = 'unknown sender';
const notABankNote = 'not a bank';

/// SMS sender cores the owner said are not a bank (setting
/// `senders.notBank`, a JSON list). Their messages are dropped again.
class BlockedSenders {
  BlockedSenders(this._db);

  final AppDatabase _db;

  static const key = 'senders.notBank';

  Future<Set<String>> load() async => _decode(await _row());

  Stream<List<String>> watch() =>
      (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((r) => _decode(r?.value).toList()..sort());

  Future<void> add(String core) async =>
      _save({...await load(), core.toUpperCase()});

  Future<void> remove(String core) async =>
      _save((await load())..remove(core.toUpperCase()));

  Future<String?> _row() async => (await (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Set<String> _decode(String? v) {
    if (v == null || v.isEmpty) return {};
    return {for (final s in jsonDecode(v) as List) s as String};
  }

  Future<void> _save(Set<String> cores) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: jsonEncode(cores.toList()..sort()),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
