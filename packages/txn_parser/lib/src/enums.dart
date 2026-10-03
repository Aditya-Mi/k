/// Values are persisted by name — rename = data migration.
enum Channel { sms, email }

enum Direction { debit, credit }

enum TxnType { upi, card, neft, imps, rtgs, atm, autopay, netBanking, other }

enum TemplateKind { transaction, mandate, ignore }
