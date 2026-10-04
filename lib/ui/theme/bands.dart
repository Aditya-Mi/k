/// Spend bands, borrowed from RBI note colours. Internal naming only — the UI
/// names them as spend ranges, never as notes (DESIGN.md Don'ts).
abstract final class Bands {
  /// Lower bound of each band in paise: <₹20, ₹20, ₹50, ₹100, ₹200, ₹500, ₹2,000.
  static const lowerMinor = [0, 2000, 5000, 10000, 20000, 50000, 200000];

  static int of(int amountMinor) {
    final a = amountMinor.abs();
    for (var i = lowerMinor.length - 1; i > 0; i--) {
      if (a >= lowerMinor[i]) return i;
    }
    return 0;
  }

  /// "Under ₹20" … "₹2,000+".
  static const ranges = [
    'Under ₹20',
    '₹20–49',
    '₹50–99',
    '₹100–199',
    '₹200–499',
    '₹500–1,999',
    '₹2,000+',
  ];

  /// Short label for the large chip: the band's lower bound.
  static const chipLabels = [
    '<20',
    '20+',
    '50+',
    '100+',
    '200+',
    '500+',
    '2000+',
  ];

  static int get count => lowerMinor.length;
}
