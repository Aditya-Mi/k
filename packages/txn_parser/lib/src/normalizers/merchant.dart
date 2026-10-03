final _trailingJunk = RegExp(r'[\s.,;:\-]+$');
final _ws = RegExp(r'\s+');
final _nonAlnum = RegExp(r'[^a-z0-9]+');

const _noise = {
  'upi', 'pvt', 'ltd', 'private', 'limited', 'india', 'in', 'llp', //
  'the', 'com', 'www', 'payment', 'payments', 'pay', 'e', 'p2m', 'p2a',
};

/// Display-friendly payee: trimmed, single-spaced, no trailing punctuation.
String cleanPayee(String raw) =>
    raw.replaceAll(_ws, ' ').replaceAll(_trailingJunk, '').trim();

/// Stable key so "SWIGGY", "swiggy.upi@axb" and "Swiggy Pvt Ltd" group
/// together. VPAs keep only the handle before '@'.
String merchantKey(String payee) {
  var s = payee.toLowerCase().trim();
  if (s.contains('@')) s = s.split('@').first;
  final tokens = s
      .split(_nonAlnum)
      .where((t) => t.isNotEmpty && !_noise.contains(t))
      .toList();
  return tokens.isEmpty ? s.replaceAll(_nonAlnum, '') : tokens.join(' ');
}
