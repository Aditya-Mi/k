final _tag = RegExp(r'<[^>]+>');
final _blockTag = RegExp(
  r'<\s*(br|/p|/div|/tr|/td|/li|/h\d)[^>]*>',
  caseSensitive: false,
);
final _styleOrScript = RegExp(
  r'<(style|script)[^>]*>.*?</\1>',
  caseSensitive: false,
  dotAll: true,
);
final _ws = RegExp(r'\s+');

const _entities = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&#8377;': '₹',
  '&rupee;': '₹',
};

/// Collapses all whitespace (incl. newlines) to single spaces so templates
/// never depend on line breaks. Strips HTML if present (email bodies).
String normalizeText(String input) {
  var s = input;
  if (s.contains('<') && s.contains('>')) {
    s = s
        .replaceAll(_styleOrScript, ' ')
        .replaceAll(_blockTag, ' ')
        .replaceAll(_tag, '');
  }
  for (final e in _entities.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  return s.replaceAll(' ', ' ').replaceAll(_ws, ' ').trim();
}
