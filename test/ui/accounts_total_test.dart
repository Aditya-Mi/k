import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/ui/screens/accounts/accounts_screen.dart';

void main() {
  final at = DateTime(2026, 10, 5);
  AccountRowData row(AccountType type, int? minor, {int? limit}) => (
    account: AccountView(
      id: '$type$minor',
      bankId: 'AXIS',
      bankName: 'Axis Bank',
      type: type,
      creditLimitMinor: limit,
    ),
    balance: minor == null
        ? null
        : AccountBalance(
            amountMinor: minor,
            asOf: at,
            source: BalanceSource.bank,
            anchorAt: at,
          ),
    emis: const [],
  );

  test('banks + cash − card owed; unknowns left out', () {
    final t = accountsTotal([
      row(AccountType.savings, 4231840),
      row(AccountType.savings, 1875133),
      row(AccountType.cash, 340000),
      // ₹1,00,000 limit, ₹85,420.50 available → ₹14,579.50 owed.
      row(AccountType.creditCard, 8542050, limit: 10000000),
      row(AccountType.creditCard, 500000), // no limit: owed unknown
      row(AccountType.current, null), // no balance yet
    ]);
    expect(t.owedMinor, 1457950);
    expect(t.totalMinor, 4989023);
  });

  test('overdrawn counts against the total', () {
    final t = accountsTotal([
      row(AccountType.savings, -50000),
      row(AccountType.cash, 20000),
    ]);
    expect(t.totalMinor, -30000);
    expect(signedInr(t.totalMinor), '−₹300');
  });
}
