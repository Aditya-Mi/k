import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  final generator = TemplateGenerator();
  const sample =
      'Your a/c XX1234 has been debited for Rs 99.00 towards NEWMERCHANT '
      'ref no 88776655 on 03-10-26. Call 18604195555 if not you. Axis Bank';

  GeneratedTemplate generate([Map<String, String>? fields]) =>
      generator.generate(
        id: 'u1',
        bankCode: 'AXIS',
        channel: Channel.sms,
        sampleText: sample,
        fieldValues:
            fields ??
            {
              'last4': '1234',
              'amount': '99.00',
              'payee': 'NEWMERCHANT',
              'ref': '88776655',
              'date': '03-10-26',
            },
        defaults: const {'direction': 'debit'},
      );

  test('generated template round-trips its own sample', () {
    final g = generate();
    expect(g.error, isNull);
    expect(g.ok, isTrue);
  });

  test('generated template parses a new message of the same shape', () {
    final g = generate();
    final engine = ParserEngine(
      banks: builtInBanks,
      userTemplates: [g.template!],
    );
    final r = engine.parse(
      RawInput(
        channel: Channel.sms,
        sender: 'AX-AXISBK-S',
        body:
            'Your a/c XX9876 has been debited for Rs 1,450.50 towards '
            'OTHER SHOP LTD ref no 11223344 on 04-10-26. Call 18001234567 '
            'if not you. Axis Bank',
        receivedAt: DateTime(2026, 10, 4, 18),
      ),
    );
    expect(r.status, ParseStatus.parsed);
    expect(r.templateId, 'u1');
    expect(r.fields.amountMinor, 145050);
    expect(r.fields.last4, '9876');
    expect(r.fields.payee, 'OTHER SHOP LTD');
    expect(r.fields.ref, '11223344');
    expect(r.fields.direction, Direction.debit);
  });

  test('learned templates can read the debit card', () {
    const text =
        'INR 500.00 debited from A/c no. XX001234 on SOME ATM 05-10-2026 '
        '10:00:00 IST. Not you? SMS BLOCKCARD XX4321 to 919951860002';
    final g = generator.generate(
      id: 'u2',
      bankCode: 'AXIS',
      channel: Channel.sms,
      sampleText: text,
      fieldValues: {'amount': '500.00', 'last4': '1234', 'card': '4321'},
      defaults: const {'direction': 'debit'},
    );
    expect(g.ok, isTrue, reason: g.error);
    final r = ParserEngine(banks: builtInBanks, userTemplates: [g.template!])
        .parse(
          RawInput(
            channel: Channel.sms,
            sender: 'AX-AXISBK-S',
            body: text.replaceAll('4321', '8765'),
            receivedAt: DateTime(2026, 10, 5, 10),
          ),
        );
    expect(r.templateId, 'u2');
    expect(r.fields.card, '8765');
  });

  test('fails clearly when a selected value is not in the text', () {
    final g = generate({'amount': '12345.00'});
    expect(g.ok, isFalse);
    expect(g.error, contains('not found'));
  });

  test('rejects unknown field names', () {
    final g = generate({'colour': 'red'});
    expect(g.ok, isFalse);
    expect(g.error, contains('unknown field'));
  });

  test('same value used twice claims distinct occurrences', () {
    final g = generator.generate(
      id: 'u2',
      bankCode: 'AXIS',
      channel: Channel.sms,
      sampleText: 'Paid Rs 100.00, balance Rs 100.00 left',
      fieldValues: {'amount': '100.00', 'balance': '100.00'},
      defaults: const {'direction': 'debit'},
    );
    expect(g.error, isNull);
  });
}
