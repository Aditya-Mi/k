import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart'
    show Channel, InstitutionKind, builtInBanks;

import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/seed/seed_data.dart';

/// A bank and the senders k reads it from (Settings → Banks).
class BankView extends Equatable {
  const BankView(
    this.id,
    this.name,
    this.sms,
    this.email, {
    this.accounts = 0,
    this.inUse = false,
    this.wallet = false,
  });

  final String id;
  final String name;
  final List<String> sms;
  final List<String> email;

  /// Live accounts shown in Accounts.
  final int accounts;

  /// "Your banks": has an account or has sent a message k kept. The rest
  /// are banks k can read but you haven't used (design 06k).
  final bool inUse;

  /// A wallet (PhonePe, Paytm…) per the parser's catalogue.
  final bool wallet;

  @override
  List<Object?> get props => [id, name, sms, email, accounts, inUse, wallet];
}

class BankRepository {
  BankRepository(this._db, {this.onRulesChanged});

  final AppDatabase _db;

  /// Parser caches sender rules; called after a change.
  final void Function()? onRulesChanged;

  Stream<List<BankView>> watchBanks() {
    final b = _db.banks;
    final r = _db.senderRules;
    final banks =
        (_db.select(b).join([
                leftOuterJoin(
                  r,
                  r.bankId.equalsExp(b.id) &
                      r.deletedAt.isNull() &
                      r.enabled.equals(true),
                ),
              ])
              // Cash is a pseudo bank: no senders to manage.
              ..where(b.deletedAt.isNull() & b.id.equals(cashBankId).not())
              ..orderBy([
                OrderingTerm.asc(b.name),
                OrderingTerm.asc(r.pattern),
              ]))
            .watch();
    final a = _db.accounts;
    final accounts =
        (_db.select(a)
              ..where((x) => x.deletedAt.isNull() & x.mergedIntoId.isNull()))
            .watch()
            .map((rows) {
              final n = <String, int>{};
              for (final x in rows) {
                n[x.bankId] = (n[x.bankId] ?? 0) + 1;
              }
              return n;
            });
    final m = _db.rawMessages;
    final messaged =
        (_db.selectOnly(m, distinct: true)
              ..addColumns([m.bankId])
              ..where(m.bankId.isNotNull() & m.deletedAt.isNull()))
            .watch()
            .map((rows) => {for (final x in rows) x.read(m.bankId)!});
    return Rx.combineLatest3(banks, accounts, messaged, (rows, perBank, seen) {
      final views = <String, (String, List<String>, List<String>)>{};
      for (final row in rows) {
        final bank = row.readTable(b);
        final entry = views.putIfAbsent(
          bank.id,
          () => (bank.name, <String>[], <String>[]),
        );
        final rule = row.readTableOrNull(r);
        if (rule == null) continue;
        (rule.channel == Channel.sms ? entry.$2 : entry.$3).add(rule.pattern);
      }
      return [
        for (final e in views.entries)
          BankView(
            e.key,
            e.value.$1,
            e.value.$2,
            e.value.$3,
            accounts: perBank[e.key] ?? 0,
            inUse: (perBank[e.key] ?? 0) > 0 || seen.contains(e.key),
            wallet: isWalletBank(e.key),
          ),
      ];
    });
  }

  /// A bank named by the owner (unknown sender 03h, Add account 10c).
  /// Reuses a bank k already has when the name means the same one: same
  /// name, or same name code, or the code is that bank's id ("SBI", "State
  /// Bank of India" and "state bank of india" all land on the catalogue's
  /// SBI). Otherwise the id is the name's code ("ZZ Bank" → "ZZ").
  Future<String> addBank(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final banks = await (_db.select(
      _db.banks,
    )..where((b) => b.deletedAt.isNull())).get();
    final code = bankCodeFor(clean);
    final same = banks
        .where(
          (b) =>
              b.name.toLowerCase() == clean.toLowerCase() ||
              b.id == code ||
              bankCodeFor(b.name) == code,
        )
        .firstOrNull;
    if (same != null) return same.id;
    final taken = {for (final b in await _db.select(_db.banks).get()) b.id};
    final base = code;
    var id = base;
    for (var n = 2; taken.contains(id); n++) {
      id = '${base}_$n';
    }
    await _db
        .into(_db.banks)
        .insert(BanksCompanion.insert(id: Value(id), name: clean));
    return id;
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

/// "HDFC Bank" → "HDFC", "IDFC First Bank" → "IDFC_FIRST",
/// "State Bank of India" → "STATE_INDIA".
String bankCodeFor(String name) {
  const filler = {'bank', 'ltd', 'limited', 'of', 'the', 'and'};
  final words = name
      .toUpperCase()
      .split(RegExp('[^A-Z0-9]+'))
      .where((w) => w.isNotEmpty && !filler.contains(w.toLowerCase()))
      .toList();
  return words.isEmpty ? 'BANK' : words.join('_');
}

final _wallets = {
  for (final b in builtInBanks)
    if (b.kind == InstitutionKind.wallet) b.code,
};

/// Wallet banks come from the parser's catalogue (`BankDefinition.kind`).
bool isWalletBank(String bankId) => _wallets.contains(bankId);
