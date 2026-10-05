/// Values are persisted by name — rename = data migration.
enum Channel { sms, email }

enum Direction { debit, credit }

enum TxnType { upi, card, neft, imps, rtgs, atm, autopay, netBanking, other }

enum TemplateKind { transaction, mandate, ignore }

/// What a BankDefinition stands for. Wallets (PhonePe, Paytm…) have no
/// account number.
enum InstitutionKind { bank, wallet }
