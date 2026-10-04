import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/app_database.dart' as db show ParserTemplate;
import '../ingest/ingestion_service.dart';
import 'field_marks.dart';
import 'review_service.dart';

/// A format the owner taught k in Review, with the message it came from.
class LearnedFormat {
  const LearnedFormat({
    required this.row,
    required this.bankName,
    required this.uses,
    this.sample,
    this.sampleText,
    this.marks = const [],
  });

  final db.ParserTemplate row;
  final String bankName;

  /// Messages this format has read (including the sample).
  final int uses;
  final RawMessage? sample;

  /// Normalized sample text and the fields this format reads from it.
  final String? sampleText;
  final List<FieldMark> marks;
}

/// List, pause and forget learned formats. Already-logged payments stay.
class LearnedFormats {
  LearnedFormats(this._db, this._ingest);

  final AppDatabase _db;
  final IngestionService _ingest;

  Stream<List<LearnedFormat>> watch() =>
      (_db.select(_db.parserTemplates)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .asyncMap((rows) async {
            final banks = {
              for (final b in await _db.select(_db.banks).get()) b.id: b.name,
            };
            return [for (final r in rows) await _view(r, banks)];
          });

  Future<LearnedFormat> _view(
    db.ParserTemplate t,
    Map<String, String> banks,
  ) async {
    final uses = _db.rawMessages.id.count();
    final count =
        await (_db.selectOnly(_db.rawMessages)
              ..addColumns([uses])
              ..where(
                _db.rawMessages.templateId.equals(t.id) &
                    _db.rawMessages.deletedAt.isNull(),
              ))
            .map((r) => r.read(uses)!)
            .getSingle();
    final sample = t.sampleRawMessageId == null
        ? null
        : await (_db.select(_db.rawMessages)
                ..where((r) => r.id.equals(t.sampleRawMessageId!)))
              .getSingleOrNull();
    String? text;
    var marks = const <FieldMark>[];
    if (sample != null) {
      text = normalizeText([?sample.subject, sample.body].join(' '));
      final read = _engineFor(t, sample).parse(
        RawInput(
          channel: sample.channel,
          sender: sample.sender,
          body: sample.body,
          subject: sample.subject,
          receivedAt: sample.receivedAt,
        ),
      );
      if (read.status == ParseStatus.parsed) {
        marks = prefillMarks(text, read.fields);
      }
    }
    return LearnedFormat(
      row: t,
      bankName: banks[t.bankId] ?? t.bankId,
      uses: count,
      sample: sample,
      sampleText: text,
      marks: marks,
    );
  }

  /// This format alone, to show what it reads from its sample.
  ParserEngine _engineFor(db.ParserTemplate t, RawMessage sample) =>
      ParserEngine(
        banks: const [],
        senderRules: [
          SenderRule(t.bankId, sample.channel, senderKeyOf(sample)),
        ],
        userTemplates: [
          ParserTemplate(
            id: t.id,
            bankCode: t.bankId,
            channel: t.channel,
            kind: t.kind,
            name: t.name,
            pattern: t.pattern,
            defaults: (jsonDecode(t.fieldDefaults) as Map).map(
              (k, v) => MapEntry(k as String, v.toString()),
            ),
            priority: t.priority,
          ),
        ],
      );

  Future<void> setEnabled(String id, bool enabled) async {
    await (_db.update(
      _db.parserTemplates,
    )..where((t) => t.id.equals(id))).write(
      ParserTemplatesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _ingest.invalidate();
  }

  /// Soft delete. Payments it already logged are kept.
  Future<void> forget(String id) async {
    final now = DateTime.now();
    await (_db.update(
      _db.parserTemplates,
    )..where((t) => t.id.equals(id))).write(
      ParserTemplatesCompanion(updatedAt: Value(now), deletedAt: Value(now)),
    );
    _ingest.invalidate();
  }
}
