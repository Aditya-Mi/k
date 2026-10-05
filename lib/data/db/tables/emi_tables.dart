import 'package:drift/drift.dart';

import '../enums.dart';
import 'ledger_tables.dart';
import 'reference_tables.dart';
import 'sync_columns.dart';

/// A purchase paid off in monthly instalments: a card purchase converted to
/// EMI, or a loan paid from a bank account. Instalment n (0-based) falls due
/// [firstDueAt] + n months.
class Emis extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<EmiKind>()();

  /// The card it is billed on, or the account a loan is paid from.
  TextColumn get accountId => text().nullable().references(Accounts, #id)();

  /// Card EMI: the purchase it came from (that row's emiId points here too).
  TextColumn get purchaseTransactionId => text().nullable()();

  /// One instalment, minor units.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();

  /// Instalments in all.
  IntColumn get count => integer()();
  DateTimeColumn get firstDueAt => dateTime()();

  /// Card EMI: true → each instalment counts as spent in its month and the
  /// purchase doesn't; false → the purchase counts once, instalments don't.
  BoolColumn get spread => boolean().withDefault(const Constant(true))();
  TextColumn get status => textEnum<EmiStatus>()();

  /// Null → global default from settings (subscriptions.reminderDays).
  IntColumn get reminderDays => integer().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
}
