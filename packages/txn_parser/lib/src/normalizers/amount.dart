final _amount = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');

/// "1,23,456.5" / "Rs. 1,299" / "INR 99.00" → minor units (paise).
/// Null when the text is not a plain amount.
int? parseAmountMinor(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'(INR|Rs\.?|₹)', caseSensitive: false), '')
      .replaceAll(',', '')
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'\.$'), '');
  final m = _amount.firstMatch(cleaned);
  if (m == null) return null;
  final major = int.parse(m.group(1)!);
  final minor = (m.group(2) ?? '0').padRight(2, '0');
  return major * 100 + int.parse(minor);
}
