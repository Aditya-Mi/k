import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  test('bank codes are unique', () {
    final codes = builtInBanks.map((b) => b.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
  });

  test('no SMS sender core sits inside another bank\'s', () {
    // SMS senders match by substring, so an overlap would misfile alerts.
    final cores = [
      for (final b in builtInBanks)
        for (final s in b.smsSenders) (b.code, s.toUpperCase()),
    ];
    for (final (bank, core) in cores) {
      for (final (other, otherCore) in cores) {
        if (bank == other) continue;
        expect(
          otherCore.contains(core),
          isFalse,
          reason: '$core in $otherCore',
        );
      }
    }
  });

  test('every mail sender belongs to one bank', () {
    final senders = [
      for (final b in builtInBanks)
        ...b.emailSenders.map((e) => e.toLowerCase()),
    ];
    expect(senders.toSet(), hasLength(senders.length));
  });

  test('catalogue banks resolve by their sender', () {
    final engine = ParserEngine(banks: builtInBanks);
    expect(engine.identifyBank(Channel.sms, 'VM-HDFCBK-S'), 'HDFC');
    expect(engine.identifyBank(Channel.sms, 'AD-SBIUPI-T'), 'SBI');
    expect(
      engine.identifyBank(Channel.email, 'ICICI Bank <alert@icicibank.com>'),
      'ICICI',
    );
  });

  test('wallets are marked, banks are the default', () {
    final byCode = {for (final b in builtInBanks) b.code: b};
    expect(byCode['PHONEPE']!.kind, InstitutionKind.wallet);
    expect(byCode['PAYTM']!.kind, InstitutionKind.wallet);
    expect(byCode['AXIS']!.kind, InstitutionKind.bank);
    expect(byCode['HDFC']!.kind, InstitutionKind.bank);
  });
}
