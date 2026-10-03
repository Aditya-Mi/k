import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  group('parseAmountMinor', () {
    test('Indian grouping and decimals', () {
      expect(parseAmountMinor('1,23,456.50'), 12345650);
      expect(parseAmountMinor('1,299'), 129900);
      expect(parseAmountMinor('99.5'), 9950);
      expect(parseAmountMinor('Rs. 250.00'), 25000);
      expect(parseAmountMinor('INR 5,000'), 500000);
      expect(parseAmountMinor('₹42'), 4200);
    });

    test('rejects non-amounts', () {
      expect(parseAmountMinor(''), isNull);
      expect(parseAmountMinor('abc'), isNull);
      expect(parseAmountMinor('1.234'), isNull);
    });
  });

  group('parseBankDate', () {
    DateTime? v(String s) => parseBankDate(s)?.value;

    test('day-first numeric with 2/4 digit years', () {
      expect(v('05-10-26'), DateTime(2026, 10, 5));
      expect(v('05/10/2026'), DateTime(2026, 10, 5));
      expect(v('05-10-26, 14:32:10'), DateTime(2026, 10, 5, 14, 32, 10));
    });

    test('month names and "at" separators', () {
      expect(v('04-Oct-2026'), DateTime(2026, 10, 4));
      expect(v('04-OCT-26 at 08:05 PM'), DateTime(2026, 10, 4, 20, 5));
      expect(v('4 September 2026 12:00 AM'), DateTime(2026, 9, 4, 0, 0));
    });

    test('BOB year-first colon format', () {
      expect(v('2026:10:05 14:32:10'), DateTime(2026, 10, 5, 14, 32, 10));
    });

    test('hasTime flag', () {
      expect(parseBankDate('05-10-26')!.hasTime, isFalse);
      expect(parseBankDate('05-10-26 10:00')!.hasTime, isTrue);
    });

    test('rejects impossible dates', () {
      expect(v('31-02-2026'), isNull);
      expect(v('05-13-2026'), isNull);
      expect(v('no date here'), isNull);
    });
  });

  group('resolveOccurredAt', () {
    final received = DateTime(2026, 10, 5, 14, 32, 20);

    test('uses parsed time when present', () {
      final d = parseBankDate('05-10-26 09:00');
      expect(resolveOccurredAt(d, received), DateTime(2026, 10, 5, 9));
    });

    test('borrows received clock for same-day date-only alerts', () {
      expect(resolveOccurredAt(parseBankDate('05-10-26'), received), received);
    });

    test('keeps midnight for older date-only alerts', () {
      expect(
        resolveOccurredAt(parseBankDate('03-10-26'), received),
        DateTime(2026, 10, 3),
      );
    });

    test('falls back to received when unparseable', () {
      expect(resolveOccurredAt(null, received), received);
    });
  });

  group('merchant', () {
    test('merchantKey groups VPA, raw and legal names', () {
      expect(merchantKey('swiggy.upi@axb'), 'swiggy');
      expect(merchantKey('SWIGGY'), 'swiggy');
      expect(merchantKey('Swiggy Pvt Ltd'), 'swiggy');
      expect(merchantKey('AMAZON PAY IN E'), 'amazon');
      expect(merchantKey('rahul.sharma@okhdfcbank'), 'rahul sharma');
    });

    test('cleanPayee trims whitespace and trailing punctuation', () {
      expect(cleanPayee('  ACME  TECH PVT LTD. '), 'ACME TECH PVT LTD');
    });
  });

  group('normalizeText', () {
    test('collapses whitespace and strips HTML', () {
      expect(
        normalizeText('<p>INR&nbsp;250.00</p><br>debited\n\n  from <b>A/c</b>'),
        'INR 250.00 debited from A/c',
      );
    });

    test('drops style blocks', () {
      expect(normalizeText('<style>p{color:red}</style><p>Hi</p>'), 'Hi');
    });
  });
}
