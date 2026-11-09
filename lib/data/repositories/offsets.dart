import 'package:txn_parser/txn_parser.dart' show Direction;

/// One row of an offset group, as the allocation needs it.
typedef OffsetRow = ({
  String id,
  String offsetId,
  Direction direction,
  int amountMinor,
  DateTime occurredAt,
});

/// What cancelling did to one payment: [cancelledMinor] of it nets against
/// the other side; [others] = how many payments it cancels with.
typedef OffsetShare = ({String offsetId, int cancelledMinor, int others});

/// Payments sharing an offset id net against each other. The smaller side
/// (all money in, or all money out) cancels in full; the same amount comes
/// off the larger side, oldest payment first. What's left counts as usual:
/// ₹3,000 dinner − 3 × ₹750 paid back = ₹750 spent; ₹10,000 from mom −
/// ₹8,000 passed on = ₹2,000 came in.
Map<String, OffsetShare> allocateOffsets(Iterable<OffsetRow> rows) {
  final groups = <String, List<OffsetRow>>{};
  for (final r in rows) {
    groups.putIfAbsent(r.offsetId, () => []).add(r);
  }
  final out = <String, OffsetShare>{};
  for (final MapEntry(key: id, value: group) in groups.entries) {
    // A payment left alone (the others deleted) counts as usual.
    if (group.length < 2) continue;
    int total(Direction d) => group
        .where((r) => r.direction == d)
        .fold(0, (s, r) => s + r.amountMinor);
    final cancel = [
      total(Direction.debit),
      total(Direction.credit),
    ].reduce((a, b) => a < b ? a : b);
    for (final d in Direction.values) {
      final side = group.where((r) => r.direction == d).toList()
        ..sort((a, b) {
          final c = a.occurredAt.compareTo(b.occurredAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      var left = cancel;
      for (final r in side) {
        final take = left < r.amountMinor ? left : r.amountMinor;
        left -= take;
        out[r.id] = (
          offsetId: id,
          cancelledMinor: take,
          others: group.length - 1,
        );
      }
    }
  }
  return out;
}

/// A payment as pass-through matching needs it.
typedef PassRow = ({
  String id,
  Direction direction,
  int amountMinor,
  DateTime occurredAt,
});

/// Money in, then most of it out soon after (mom's cash passed on): pairs
/// worth asking "do these cancel out?". A credit pairs with the closest
/// debit within [window] after it worth [minShare]–100% of it; each payment
/// pairs once. Callers leave out what can't cancel out (transfers, income,
/// neither, already linked or dismissed).
List<(String credit, String debit)> suggestPassThroughs(
  Iterable<PassRow> rows, {
  Duration window = const Duration(days: 3),
  double minShare = 0.75,
}) {
  final sorted = rows.toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final debits = sorted.where((r) => r.direction == Direction.debit).toList();
  final used = <String>{};
  final out = <(String, String)>[];
  for (final c in sorted.where((r) => r.direction == Direction.credit)) {
    for (final d in debits) {
      if (used.contains(d.id)) continue;
      if (!d.occurredAt.isAfter(c.occurredAt)) continue;
      if (d.occurredAt.difference(c.occurredAt) > window) break;
      if (d.amountMinor > c.amountMinor ||
          d.amountMinor < c.amountMinor * minShare) {
        continue;
      }
      used.add(d.id);
      out.add((c.id, d.id));
      break;
    }
  }
  return out;
}
