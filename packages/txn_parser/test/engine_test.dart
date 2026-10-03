import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  final received = DateTime(2026, 10, 5, 12);

  RawInput sms(String sender, String body) => RawInput(
    channel: Channel.sms,
    sender: sender,
    body: body,
    receivedAt: received,
  );

  group('sender identification', () {
    final engine = ParserEngine(banks: builtInBanks);

    test('SMS header core matches any operator prefix/suffix', () {
      expect(engine.identifyBank(Channel.sms, 'AX-AXISBK-S'), 'AXIS');
      expect(engine.identifyBank(Channel.sms, 'jd-kotakb'), 'KOTAK');
      expect(engine.identifyBank(Channel.sms, 'VM-BOBCRD-T'), 'BOB');
    });

    test('email matches domain and subdomains, not lookalikes', () {
      expect(
        engine.identifyBank(Channel.email, 'Axis <alerts@axisbank.com>'),
        'AXIS',
      );
      expect(
        engine.identifyBank(Channel.email, 'cc@alerts.kotak.com'),
        'KOTAK',
      );
      expect(
        engine.identifyBank(Channel.email, 'phish@notkotak.com'),
        isNull,
      );
    });

    test('non-bank sender is dropped', () {
      final r = engine.parse(sms('AX-SWIGGY', 'Your order is on the way'));
      expect(r.status, ParseStatus.notBank);
    });

    test('custom sender rules override defaults', () {
      final custom = ParserEngine(
        banks: builtInBanks,
        senderRules: const [SenderRule('AXIS', Channel.sms, 'AXISNEW')],
      );
      expect(custom.identifyBank(Channel.sms, 'AX-AXISNEW-S'), 'AXIS');
      expect(custom.identifyBank(Channel.sms, 'AX-AXISBK-S'), isNull);
    });
  });

  group('templates', () {
    test('user templates beat built-ins by priority', () {
      final engine = ParserEngine(
        banks: builtInBanks,
        userTemplates: [
          ParserTemplate(
            id: 'user_1',
            bankCode: 'AXIS',
            channel: Channel.sms,
            priority: 10,
            pattern: r'INR (?<amount>[\d,.]+) debited',
            defaults: const {'direction': 'debit'},
          ),
        ],
      );
      final r = engine.parse(
        sms(
          'AX-AXISBK-S',
          'INR 250.00 debited\nA/c no. XX1234\n05-10-26, 14:32:10\n'
              'UPI/P2M/427812345678/SWIGGY\nNot you? Axis Bank',
        ),
      );
      expect(r.templateId, 'user_1');
      expect(r.status, ParseStatus.parsed);
    });

    test('ignore templates mark messages as non-transactions', () {
      final engine = ParserEngine(
        banks: builtInBanks,
        userTemplates: [
          ParserTemplate(
            id: 'ignore_statement',
            bankCode: 'AXIS',
            channel: Channel.sms,
            kind: TemplateKind.ignore,
            priority: 1,
            pattern: r'statement .* is generated',
          ),
        ],
      );
      final r = engine.parse(
        sms('AX-AXISBK-S', 'Your card statement for Sep is generated'),
      );
      expect(r.status, ParseStatus.nonTransaction);
      expect(r.templateId, 'ignore_statement');
    });

    test('match without direction goes to review with missing field', () {
      final engine = ParserEngine(
        banks: builtInBanks,
        userTemplates: [
          ParserTemplate(
            id: 'no_dir',
            bankCode: 'AXIS',
            channel: Channel.sms,
            priority: 1,
            pattern: r'Amount (?<amount>[\d,.]+)',
          ),
        ],
      );
      final r = engine.parse(sms('AX-AXISBK-S', 'Amount 100.00 processed'));
      expect(r.status, ParseStatus.needsReview);
      expect(r.missing, ['direction']);
      expect(r.fields.amountMinor, 10000);
    });

    test('email falls back to SMS templates for the same bank', () {
      final engine = ParserEngine(banks: builtInBanks);
      final r = engine.parse(
        RawInput(
          channel: Channel.email,
          sender: 'alerts@axisbank.com',
          body:
              'INR 2,000.00 withdrawn at ATM S1ANDL123 from A/c no. XX1234 on '
              '02-10-26 18:44:12. Avl Bal INR 10,345.67',
          receivedAt: received,
        ),
      );
      expect(r.templateId, 'axis_sms_atm');
      expect(r.fields.txnType, TxnType.atm);
    });
  });
}
