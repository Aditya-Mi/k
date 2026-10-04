import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:txn_parser/txn_parser.dart' show Channel;

import '../db/app_database.dart' hide ParserTemplate, SenderRule;

/// A bank and the senders k reads it from (Settings → Banks).
class BankView extends Equatable {
  const BankView(this.id, this.name, this.sms, this.email);

  final String id;
  final String name;
  final List<String> sms;
  final List<String> email;

  @override
  List<Object?> get props => [id, name, sms, email];
}

class BankRepository {
  BankRepository(this._db, {this.onRulesChanged});

  final AppDatabase _db;

  /// Parser caches sender rules; called after a change.
  final void Function()? onRulesChanged;

  Stream<List<BankView>> watchBanks() {
    final b = _db.banks;
    final r = _db.senderRules;
    return (_db.select(b).join([
            leftOuterJoin(
              r,
              r.bankId.equalsExp(b.id) &
                  r.deletedAt.isNull() &
                  r.enabled.equals(true),
            ),
          ])
          ..where(b.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(b.name), OrderingTerm.asc(r.pattern)]))
        .watch()
        .map((rows) {
          final banks = <String, (String, List<String>, List<String>)>{};
          for (final row in rows) {
            final bank = row.readTable(b);
            final entry = banks.putIfAbsent(
              bank.id,
              () => (bank.name, <String>[], <String>[]),
            );
            final rule = row.readTableOrNull(r);
            if (rule == null) continue;
            (rule.channel == Channel.sms ? entry.$2 : entry.$3).add(
              rule.pattern,
            );
          }
          return [
            for (final e in banks.entries)
              BankView(e.key, e.value.$1, e.value.$2, e.value.$3),
          ];
        });
  }

  /// Adds (or re-enables) a sender: an SMS header core like "AXISBK", or an
  /// email address / domain like "alerts@axis.bank.in".
  Future<void> addSender(String bankId, Channel channel, String pattern) async {
    final p = channel == Channel.sms
        ? pattern.trim().toUpperCase()
        : pattern.trim().toLowerCase();
    if (p.isEmpty) return;
    final existing =
        await (_db.select(_db.senderRules)..where(
              (r) => r.channel.equalsValue(channel) & r.pattern.equals(p),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (_db.update(
        _db.senderRules,
      )..where((r) => r.id.equals(existing.id))).write(
        SenderRulesCompanion(
          bankId: Value(bankId),
          enabled: const Value(true),
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await _db
          .into(_db.senderRules)
          .insert(
            SenderRulesCompanion.insert(
              bankId: bankId,
              channel: channel,
              pattern: p,
            ),
          );
    }
    onRulesChanged?.call();
  }
}
