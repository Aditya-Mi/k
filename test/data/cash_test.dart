import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' show Account, Transaction;
import 'package:k/data/db/enums.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/ui/screens/transactions/transactions_cubit.dart';
import 'package:txn_parser/txn_parser.dart';

final _t0 = DateTime(2026, 10);

Account _cash({int? manual, DateTime? at}) => Account(
  id: 'acc_cash',
  createdAt: _t0,
  updatedAt: _t0,
  bankId: 'CASH',
  type: AccountType.cash,
  currency: 'INR',
  autoCreated: false,
  manualBalanceMinor: manual,
  manualBalanceAt: at,
);

var _n = 0;
Transaction _row(
  int rupees,
  DateTime at, {
  String account = 'acc_axis',
  Direction direction = Direction.debit,
  TxnType type = TxnType.upi,
}) => Transaction(
  id: '${_n++}',
  createdAt: at,
  updatedAt: at,
  accountId: account,
  amountMinor: rupees * 100,
  currency: 'INR',
  direction: direction,
  txnType: type,
  occurredAt: at,
  userEdited: false,
  autoTransferOff: false,
  origin: TxnOrigin.user,
);

void main() {
  test('cash: ATM withdrawals add, cash payments subtract', () {
    final atm = [_row(11000, DateTime(2026, 10, 1), type: TxnType.atm)];
    final cash = [
      _row(10000, DateTime(2026, 10, 2), account: 'acc_cash'),
      _row(200, DateTime(2026, 10, 3), account: 'acc_cash'),
    ];
    expect(computeCashBalance(_cash(), cash, atm)!.amountMinor, 80000);
    expect(computeCashBalance(_cash(), const [], const []), isNull);
  });

  test('cash: a counted figure resets, only later moves apply', () {
    final atm = [
      _row(5000, DateTime(2026, 10, 1), type: TxnType.atm),
      _row(2000, DateTime(2026, 10, 5), type: TxnType.atm),
    ];
    final cash = [_row(300, DateTime(2026, 10, 6), account: 'acc_cash')];
    final b = computeCashBalance(
      _cash(manual: 150000, at: DateTime(2026, 10, 4)),
      cash,
      atm,
    )!;
    expect(b.amountMinor, 150000 + 200000 - 30000);
    expect(b.estimatedFrom, 2);
  });

  test('rent from ATM cash is counted once, at the ATM', () {
    const axis = AccountView(
      id: 'acc_axis',
      bankId: 'AXIS',
      bankName: 'Axis Bank',
      type: AccountType.savings,
    );
    const cash = AccountView(
      id: 'acc_cash',
      bankId: 'CASH',
      bankName: 'Cash',
      type: AccountType.cash,
    );
    TxnView v(AccountView a, TxnType type) => TxnView(
      id: '${_n++}',
      amountMinor: 1100000,
      currency: 'INR',
      direction: Direction.debit,
      txnType: type,
      occurredAt: DateTime(2026, 10, 2),
      payee: 'Rent',
      sourceCount: 0,
      account: a,
    );
    final s = summarize(_t0, [v(axis, TxnType.atm), v(cash, TxnType.other)]);
    expect(s.spentMinor, 1100000);
    expect(s.spends, 1);
  });
}
