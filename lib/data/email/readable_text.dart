/// An email body as a person reads it: HTML turned into lines, entities
/// decoded, layout padding (nbsp, tabs, runs of spaces, stacked blank lines)
/// removed. Display only; parsing and review marks use the stored body.
String readableEmail(String body) {
  var s = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (_looksHtml.hasMatch(s)) {
    s = s
        .replaceAll(_hidden, ' ')
        .replaceAll(_lineBreak, '\n')
        .replaceAll(_cellEnd, ' ')
        .replaceAll(_tag, '');
    s = _decodeEntities(s);
  }
  s = s.replaceAll(_invisible, ' ');
  final lines = [
    for (final line in s.split('\n')) line.replaceAll(_spaces, ' ').trim(),
  ];
  return lines.join('\n').replaceAll(_blankRun, '\n\n').trim();
}

final _looksHtml = RegExp(
  r'<(?:html|body|div|p|br|table|td|span|a|img|font|center)\b',
  caseSensitive: false,
);
final _hidden = RegExp(
  r'<!--.*?-->|<(style|script|head|title)\b.*?</\1\s*>',
  caseSensitive: false,
  dotAll: true,
);
final _lineBreak = RegExp(
  r'<br\s*/?>|</(?:p|div|tr|li|h[1-6]|table|blockquote|center)\s*>',
  caseSensitive: false,
);
final _cellEnd = RegExp(r'</t[dh]\s*>', caseSensitive: false);
final _tag = RegExp(r'<[^>]*>');
final _invisible = RegExp('[ ​‌‍﻿\t]');
final _spaces = RegExp(r' {2,}');
final _blankRun = RegExp(r'\n{3,}');

const _named = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'ndash': '–',
  'mdash': '—',
  'bull': '•',
  'middot': '·',
  'hellip': '…',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'rupee': '₹',
};

String _decodeEntities(String s) =>
    s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#')) {
        final code = e[1] == 'x' || e[1] == 'X'
            ? int.tryParse(e.substring(2), radix: 16)
            : int.tryParse(e.substring(1));
        return code == null || code > 0x10FFFF
            ? m[0]!
            : String.fromCharCode(code);
      }
      return _named[e.toLowerCase()] ?? m[0]!;
    });
