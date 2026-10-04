import '../db/app_database.dart';

/// Every live payment as CSV (RFC 4180), oldest first, for spreadsheets.
/// Amounts are rupees with two decimals; debits negative.
class CsvExport {
  CsvExport(this._db);

  final AppDatabase _db;

  static const columns = [
    'date',
    'time',
    'amount',
    'currency',
    'direction',
    'payee',
    'account',
    'category',
    'type',
    'note',
    'ref',
    'self_transfer',
  ];

  Future<String> build() async {
    final rows = await _db.customSelect('''
      SELECT t.occurred_at, t.amount_minor, t.currency, t.direction,
             t.txn_type, t.notes, t.ref_no, t.transfer_id,
             COALESCE(m.display_name, t.payee_raw) AS payee,
             c.name AS category,
             b.name AS bank, a.nickname, a.last4
      FROM transactions t
      LEFT JOIN merchants m ON m.id = t.merchant_id
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN accounts a ON a.id = t.account_id
      LEFT JOIN banks b ON b.id = a.bank_id
      WHERE t.deleted_at IS NULL
      ORDER BY t.occurred_at
    ''').get();
    final out = StringBuffer()..write('${columns.join(',')}\r\n');
    for (final r in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        r.read<int>('occurred_at') * 1000,
      );
      final minor = r.read<int>('amount_minor');
      final debit = r.read<String>('direction') == 'debit';
      final nickname = r.readNullable<String>('nickname');
      final last4 = r.readNullable<String>('last4');
      final bank = r.readNullable<String>('bank');
      final account =
          nickname ?? [?bank, if (last4 != null) '··$last4'].join(' ');
      out.write(
        [
          _date(at),
          '${_pad2(at.hour)}:${_pad2(at.minute)}',
          '${debit ? '-' : ''}${minor ~/ 100}.${_pad2(minor % 100)}',
          r.read<String>('currency'),
          debit ? 'paid' : 'received',
          r.readNullable<String>('payee'),
          account,
          r.readNullable<String>('category'),
          r.read<String>('txn_type'),
          r.readNullable<String>('notes'),
          r.readNullable<String>('ref_no'),
          r.readNullable<String>('transfer_id') == null ? '' : 'yes',
        ].map(_cell).join(','),
      );
      out.write('\r\n');
    }
    return out.toString();
  }

  static String _date(DateTime d) =>
      '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Quotes when needed; a leading =,+,-,@ gets a ' so spreadsheets don't
  /// run a payee name as a formula. Amounts are written before this and
  /// start with a digit or '-' followed by a digit, so they're left alone.
  static String _cell(String? v) {
    if (v == null || v.isEmpty) return '';
    var s = v;
    if (RegExp(r'^[=+@]|^-[^0-9]').hasMatch(s)) s = "'$s";
    if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
    return s;
  }
}
