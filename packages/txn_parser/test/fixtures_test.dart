import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:txn_parser/txn_parser.dart';

/// Runs every case in test/fixtures/*.json. To cover a new format, paste the
/// real (masked) message into the bank's fixture file with expected fields;
/// only keys present under "expected" are asserted.
void main() {
  final engine = ParserEngine(banks: builtInBanks);
  final files = Directory('test/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final cases = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    group(file.uri.pathSegments.last, () {
      for (final c in cases.cast<Map<String, dynamic>>()) {
        test(c['name'], () {
          final result = engine.parse(
            RawInput(
              channel: Channel.values.byName(c['channel'] as String),
              sender: c['sender'] as String,
              subject: c['subject'] as String?,
              body: c['body'] as String,
              receivedAt: DateTime.parse(c['receivedAt'] as String),
            ),
          );
          _expectMatches(result, c['expected'] as Map<String, dynamic>);
        });
      }
    });
  }
}

void _expectMatches(ParseResult r, Map<String, dynamic> expected) {
  final actual = <String, Object?>{
    'status': r.status.name,
    'kind': r.kind.name,
    'templateId': r.templateId,
    'note': r.note,
    ...r.fields.toMap(),
  };
  for (final MapEntry(:key, :value) in expected.entries) {
    final want = (key == 'occurredAt' || key == 'dueDate')
        ? DateTime.parse(value as String).toIso8601String()
        : value;
    expect(actual[key], want, reason: '$key — $r');
  }
}
