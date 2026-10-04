import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

/// The fallback must recover every field of the real (masked) fixtures on
/// its own, so a bank changing its wording still pre-fills the review form.
/// On every other fixture it may leave a field empty but never guess wrong.
void main() {
  final engine = ParserEngine(
    banks: [
      for (final b in builtInBanks)
        BankDefinition(
          code: b.code,
          name: b.name,
          smsSenders: b.smsSenders,
          emailSenders: b.emailSenders,
          templates: const [],
        ),
    ],
  );
  const guessed = [
    'amountMinor', 'direction', 'last4', 'payee', 'ref', 'balanceMinor', //
  ];

  final files =
      Directory('test/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final cases = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((c) => c['expected']['status'] != 'notBank');
    group('fallback ${file.uri.pathSegments.last}', () {
      for (final c in cases) {
        test(c['name'], () {
          final r = engine.parse(
            RawInput(
              channel: Channel.values.byName(c['channel'] as String),
              sender: c['sender'] as String,
              subject: c['subject'] as String?,
              body: c['body'] as String,
              receivedAt: DateTime.parse(c['receivedAt'] as String),
            ),
          );
          final actual = r.fields.toMap();
          final expected = c['expected'] as Map<String, dynamic>;
          final real = (c['name'] as String).startsWith('Real');
          for (final key in guessed.where(expected.containsKey)) {
            expect(
              actual[key],
              real ? expected[key] : anyOf(isNull, expected[key]),
              reason: '$key — $r',
            );
          }
        });
      }
    });
  }
}
