import 'enums.dart';

Direction? directionFromWord(String? word) {
  if (word == null) return null;
  final w = word.toLowerCase().replaceAll('.', '');
  if (Direction.values.any((d) => d.name == w)) return Direction.values.byName(w);
  const debit = {'debited', 'dr', 'spent', 'sent', 'paid', 'withdrawn'};
  const credit = {'credited', 'cr', 'received', 'deposited'};
  if (debit.contains(w)) return Direction.debit;
  if (credit.contains(w)) return Direction.credit;
  return null;
}

TxnType? txnTypeFromWord(String? word) {
  if (word == null) return null;
  final w = word.toLowerCase();
  for (final t in TxnType.values) {
    if (t.name.toLowerCase() == w) return t;
  }
  return null;
}

/// Best guess from message text when a template doesn't pin the type.
TxnType inferTxnType(String text, {required bool isMandate}) {
  if (isMandate) return TxnType.autopay;
  final t = text.toLowerCase();
  bool has(String pattern) => RegExp(pattern).hasMatch(t);
  if (has(r'\batm\b') && has(r'withdrawn|withdrawal')) return TxnType.atm;
  if (has(r'\bupi\b') || has(r'[\w.\-]+@[a-z]+\b(?!\.)')) return TxnType.upi;
  if (has(r'\bimps\b')) return TxnType.imps;
  if (has(r'\bneft\b')) return TxnType.neft;
  if (has(r'\brtgs\b')) return TxnType.rtgs;
  if (has(r'\bcard\b')) return TxnType.card;
  return TxnType.other;
}
