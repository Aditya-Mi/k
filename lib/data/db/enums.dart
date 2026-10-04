/// App-side enums persisted by name — rename = data migration.
enum AccountType { savings, current, creditCard, debitCard, wallet, other }

enum EmailAuthType { oauth, imap }

/// Where a transaction came from: a bank message, or added by the owner
/// (e.g. the untracked side of a self transfer).
enum TxnOrigin { message, user }

enum RawMessageStatus { pending, parsed, needsReview, nonTransaction, ignored }

enum RuleMatchType { merchant, keyword }

enum RuleOrigin { system, user }

enum SubscriptionFrequency { monthly, quarterly, halfYearly, yearly, custom }

enum SubscriptionStatus { suggested, active, dismissed, cancelled }

enum SubscriptionSource { detected, mandate, manual }

enum UpcomingChargeStatus { pending, matched, expired, cancelled }
