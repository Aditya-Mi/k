import 'enums.dart';
import 'normalizers/text.dart';
import 'template.dart';

/// Result of turning a user's review correction into a reusable template.
class GeneratedTemplate {
  const GeneratedTemplate._(this.template, this.error);

  final ParserTemplate? template;

  /// Why generation failed (value not found in text, groups don't round-trip).
  final String? error;

  bool get ok => template != null;
}

/// Builds a template from one sample: the user marks which substring is each
/// field; literal text between fields becomes the anchor, digit runs in it are
/// generalised to \d+, and only a few words of lead-in/trailer are kept so
/// changing footers (phone numbers, links) don't break matching.
class TemplateGenerator {
  static const _contextWords = 3;

  static const _groupPatterns = {
    Fields.amount: r'[\d,]+(?:\.\d{1,2})?',
    Fields.balance: r'[\d,]+(?:\.\d{1,2})?',
    Fields.last4: r'\d{4}',
    Fields.ref: r'[A-Za-z0-9]+',
    Fields.mandateRef: r'[A-Za-z0-9]+',
    Fields.direction: r'[A-Za-z]+',
    Fields.type: r'[A-Za-z]+',
    Fields.currency: r'[A-Za-z₹.]+',
  };

  GeneratedTemplate generate({
    required String id,
    required String bankCode,
    required Channel channel,
    required String sampleText,
    required Map<String, String> fieldValues,
    TemplateKind kind = TemplateKind.transaction,
    Map<String, String> defaults = const {},
    int priority = 10,
  }) {
    final text = normalizeText(sampleText);
    final spans = <({String field, int start, int end})>[];

    for (final MapEntry(key: field, value: raw) in fieldValues.entries) {
      if (!Fields.all.contains(field)) {
        return GeneratedTemplate._(null, 'unknown field "$field"');
      }
      final value = normalizeText(raw);
      if (value.isEmpty) continue;
      final start = _findFree(text, value, spans);
      if (start == null) {
        return GeneratedTemplate._(null, '"$value" ($field) not found in text');
      }
      spans.add((field: field, start: start, end: start + value.length));
    }
    if (spans.isEmpty) {
      return const GeneratedTemplate._(null, 'no fields selected');
    }
    spans.sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      var literal = text.substring(cursor, span.start);
      if (i == 0) literal = _lastWords(literal);
      buffer.write(_literal(literal));

      final isLast = i == spans.length - 1;
      final trailer = isLast ? _firstWords(text.substring(span.end)) : '';
      buffer.write('(?<${span.field}>${_groupFor(span.field, lazy: !isLast || trailer.isNotEmpty)})');
      if (isLast) buffer.write(_literal(trailer));
      cursor = span.end;
    }

    final template = ParserTemplate(
      id: id,
      bankCode: bankCode,
      channel: channel,
      kind: kind,
      name: 'user: $id',
      pattern: buffer.toString(),
      defaults: defaults,
      priority: priority,
    );

    final error = _verify(template, text, spans);
    return error == null
        ? GeneratedTemplate._(template, null)
        : GeneratedTemplate._(null, error);
  }

  String _groupFor(String field, {required bool lazy}) =>
      _groupPatterns[field] ?? (lazy ? '.+?' : '.+');

  /// First occurrence not overlapping an already-claimed span.
  int? _findFree(String text, String value, List<({String field, int start, int end})> taken) {
    var from = 0;
    while (true) {
      final i = text.toLowerCase().indexOf(value.toLowerCase(), from);
      if (i < 0) return null;
      final end = i + value.length;
      if (!taken.any((s) => i < s.end && end > s.start)) return i;
      from = i + 1;
    }
  }

  String _lastWords(String s) {
    final words = s.split(' ');
    if (words.length <= _contextWords + 1) return s;
    return words.sublist(words.length - _contextWords - 1).join(' ');
  }

  String _firstWords(String s) {
    final words = s.split(' ');
    if (words.length <= _contextWords + 1) return s;
    return words.sublist(0, _contextWords + 1).join(' ');
  }

  /// Escapes literal text, generalising digit runs and spaces.
  String _literal(String s) {
    final out = StringBuffer();
    final digits = RegExp(r'\d+');
    var i = 0;
    for (final m in digits.allMatches(s)) {
      out.write(_escapeSpaces(s.substring(i, m.start)));
      out.write(r'\d+');
      i = m.end;
    }
    out.write(_escapeSpaces(s.substring(i)));
    return out.toString();
  }

  String _escapeSpaces(String s) =>
      s.split(' ').map(RegExp.escape).join(r'\s+');

  String? _verify(
    ParserTemplate t,
    String text,
    List<({String field, int start, int end})> spans,
  ) {
    final m = t.regex.firstMatch(text);
    if (m == null) return 'generated pattern does not match the sample';
    for (final s in spans) {
      final expected = text.substring(s.start, s.end).toLowerCase();
      final got = m.namedGroup(s.field)?.trim().toLowerCase();
      if (got != expected) {
        return '${s.field}: expected "$expected", got "$got"';
      }
    }
    return null;
  }
}
