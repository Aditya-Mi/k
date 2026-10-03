import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../enums.dart';
import 'reference_tables.dart';
import 'settings_tables.dart';
import 'subscription_tables.dart';
import 'sync_columns.dart';

class Accounts extends Table with SyncColumns {
  TextColumn get bankId => text().references(Banks, #id)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get last4 => text().nullable()();
  TextColumn get nickname => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  BoolColumn get autoCreated => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {bankId, last4},
  ];
}

@TableIndex(name: 'raw_messages_status', columns: {#status})
class RawMessages extends Table with SyncColumns {
  TextColumn get channel => textEnum<Channel>()();
  TextColumn get bankId => text().nullable().references(Banks, #id)();
  TextColumn get sender => text()();
  TextColumn get subject => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();

  /// SMS provider _id, Gmail message id, or IMAP UID.
  TextColumn get externalId => text().nullable()();
  TextColumn get emailAccountId =>
      text().nullable().references(EmailAccounts, #id)();
  IntColumn get simSlot => integer().nullable()();

  /// sha256(channel|sender|receivedAt|body) — makes ingestion idempotent.
  TextColumn get contentHash => text().unique()();
  TextColumn get status => textEnum<RawMessageStatus>()();
  TextColumn get templateId => text().nullable()();
  TextColumn get parseNote => text().nullable()();
}

@TableIndex(name: 'txn_ref', columns: {#refNo})
@TableIndex(name: 'txn_dedup', columns: {#accountId, #amountMinor, #occurredAt})
@TableIndex(name: 'txn_occurred', columns: {#occurredAt})
class Transactions extends Table with SyncColumns {
  TextColumn get accountId => text().nullable().references(Accounts, #id)();

  /// Paise for INR; always minor units of [currency].
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get direction => textEnum<Direction>()();
  TextColumn get txnType => textEnum<TxnType>()();
  TextColumn get merchantId => text().nullable().references(Merchants, #id)();
  TextColumn get payeeRaw => text().nullable()();
  TextColumn get refNo => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  IntColumn get balanceMinor => integer().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get subscriptionId =>
      text().nullable().references(Subscriptions, #id)();
  TextColumn get notes => text().nullable()();

  /// Set once the user edits — re-parsing/dedup must not overwrite it.
  BoolColumn get userEdited => boolean().withDefault(const Constant(false))();
}

/// Dedup link: one transaction ← many raw messages (SMS + email).
class TransactionSources extends Table with SyncColumns {
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get rawMessageId => text().unique().references(RawMessages, #id)();
}
