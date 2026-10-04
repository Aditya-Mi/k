import 'package:intl/intl.dart';

final _rupees = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _rupeesPaise = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// Indian grouping (₹1,12,000); paise only when [paise] (detail/review).
String inr(int minor, {bool paise = false, bool plus = false}) {
  final f = paise ? _rupeesPaise : _rupees;
  final s = f.format(minor.abs() / 100);
  return '${plus ? '+' : ''}$s';
}

/// List rows: whole rupees unless the source carried paise.
String inrRow(int minor, {bool plus = false}) =>
    inr(minor, paise: minor % 100 != 0, plus: plus);

final _count = NumberFormat.decimalPattern('en_IN');

/// Counts with Indian grouping (1,284 · 1,12,000).
String grouped(int n) => _count.format(n);

final _time = DateFormat('HH:mm');
final _dayShort = DateFormat('EEE d MMM');
final _dayMonth = DateFormat('d MMM');
final _monthShort = DateFormat('MMM');
final _monthYearShort = DateFormat('MMM yyyy');
final _monthYear = DateFormat('MMMM yyyy');
final _full = DateFormat('EEE d MMM yyyy, HH:mm');
final _fullDay = DateFormat('d MMM yyyy');

String hhmm(DateTime d) => _time.format(d);
String dayShort(DateTime d) => _dayShort.format(d);
String dayMonth(DateTime d) => _dayMonth.format(d);
String monthYear(DateTime d) => _monthYear.format(d);

/// "Jul", or "Jul 2025" when not this year.
String monthShort(DateTime d, DateTime now) =>
    d.year == now.year ? _monthShort.format(d) : _monthYearShort.format(d);
String fullStamp(DateTime d) => _full.format(d);
String fullDay(DateTime d) => _fullDay.format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Today · Sun 5 Oct", "Yesterday · Sat 4 Oct", "Fri 3 Oct".
String dayLabel(DateTime day, DateTime now) {
  final diff = dateOnly(now).difference(dateOnly(day)).inDays;
  final base = dayShort(day);
  return switch (diff) {
    0 => 'Today · $base',
    1 => 'Yesterday · $base',
    _ => day.year == now.year ? base : '$base ${day.year}',
  };
}
