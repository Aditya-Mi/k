/// App-side enums persisted by name — rename = data migration.
enum AccountType { savings, current, creditCard, debitCard, wallet, other }

enum EmailAuthType { oauth, imap }

enum RawMessageStatus { pending, parsed, needsReview, nonTransaction, ignored }

enum RuleMatchType { merchant, keyword }

enum RuleOrigin { system, user }

enum SubscriptionFrequency { monthly, quarterly, halfYearly, yearly, custom }

enum SubscriptionStatus { suggested, active, dismissed, cancelled }

enum SubscriptionSource { detected, mandate, manual }

enum UpcomingChargeStatus { pending, matched, expired, cancelled }
