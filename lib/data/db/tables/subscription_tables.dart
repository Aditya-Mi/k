import 'package:drift/drift.dart';

import '../enums.dart';
import 'ledger_tables.dart';
import 'reference_tables.dart';
import 'sync_columns.dart';

class Subscriptions extends Table with SyncColumns {
  TextColumn get merchantId => text().nullable().references(Merchants, #id)();
  TextColumn get name => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get frequency => textEnum<SubscriptionFrequency>()();

  /// Cycle length in days; authoritative when frequency == custom.
  IntColumn get intervalDays => integer()();
  DateTimeColumn get lastChargedAt => dateTime().nullable()();
  IntColumn get lastAmountMinor => integer().nullable()();
  DateTimeColumn get nextExpectedAt => dateTime().nullable()();
  BoolColumn get priceChanged => boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<SubscriptionStatus>()();
  BoolColumn get unused => boolean().withDefault(const Constant(false))();
  TextColumn get source => textEnum<SubscriptionSource>()();

  /// Null → global default from settings.
  IntColumn get reminderDays => integer().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
}

/// From AutoPay / e-mandate "will be debited" alerts.
class UpcomingCharges extends Table with SyncColumns {
  TextColumn get subscriptionId =>
      text().nullable().references(Subscriptions, #id)();
  TextColumn get merchantId => text().nullable().references(Merchants, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  DateTimeColumn get dueDate => dateTime()();

  /// UMRN / mandate reference.
  TextColumn get mandateRef => text().nullable()();
  TextColumn get rawMessageId =>
      text().nullable().references(RawMessages, #id)();
  TextColumn get status => textEnum<UpcomingChargeStatus>()();
  TextColumn get matchedTransactionId =>
      text().nullable().references(Transactions, #id)();
}
