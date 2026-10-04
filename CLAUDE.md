# k — personal payment logger

> New session? Read `HANDOFF.md` first (current state, decisions, next step).

Sideloaded Android app (personal use, never Play Store). Reads bank SMS + bank alert emails, logs transactions, detects subscriptions. All data on-device; never send message contents off-device.

## Working rules
- Implement directly — do NOT show diffs or wait for approval before writing files in this project (overrides the global "show plan + diffs" rule). Still confirm before destructive/irreversible actions.
- New screens: design in Pencil (`design/k.pen`) first, export to `design/screens/`, then build in Flutter.
- Two Claude sessions may work here at once:
  - **Main session** — design (Pencil `.pen` + `/impeccable`) and app phases (`lib/`, `android/`, `test/`).
  - **Parser session** — only `packages/txn_parser/` (templates, fixtures, tests). Must not edit `lib/` or `android/`; if a schema/app change is needed, write it down for the main session.
  - Commit your own files only (`git add <paths>`, never `git add -A`); pull in the other session's work with `git status` before editing shared files.

## Stack
Flutter (Dart 3.13) · flutter_bloc + get_it · drift + SQLite3MultipleCiphers (encrypted via `sqlite3` build hooks, `hooks.user_defines.sqlite3.source: sqlite3mc` in pubspec — do NOT add sqlcipher_flutter_libs / sqlite3_flutter_libs) · workmanager · native Kotlin only for SMS capture. minSdk 26. Device: Nothing Phone 2.

## Layout
- `packages/txn_parser/` — pure Dart parser (no Flutter). Engine: sender → bank, prefilter (OTP/promo/declined), template match, normalize. Banks in `lib/src/banks/<bank>.dart`, registered in `registry.dart`.
- `lib/data/db/` — drift tables (`tables/`), `app_database.dart`, `connection.dart` (encryption), `seed/`.
- `lib/core/` — ids (UUIDv7), security (DB key in secure storage).
- `lib/platform/` — `SmsBridge` (channels `k/sms`, `k/sms_events`); native side in `android/.../k/sms/`.
- `lib/data/ingest/` — `IngestionService` (message → raw_messages → transaction), `SmsSync` (queue drain, inbox catch-up, history). `lib/data/repositories/` — read models + edits.
- `lib/ui/` — `theme/` (KColors, KText, Bands), `widgets/`, `screens/`; `lib/app/` — app shell + `SmsController`.
- `design/k.pen` — Pencil design (open only via Pencil MCP tools; file is encrypted). `design/screens/*.png` — exported screens. `DESIGN.md` — design system (tokens, type, components, rules) to implement in Flutter; `PRODUCT.md` — product context.

## Commands
```
cd packages/txn_parser && dart test      # parser tests (fixtures + unit)
flutter test                             # app/DB tests
dart run build_runner build              # after any drift table change
flutter analyze
flutter build apk --debug
```

## Conventions
- Money: `amountMinor` int (paise) + `currency` text. Never doubles.
- Enums persisted by name (`textEnum`) — renaming a value needs a migration.
- Every synced table uses `SyncColumns` (UUIDv7 text id, createdAt, updatedAt, deletedAt). Soft delete only. Seed rows use stable string ids (`cat_food`, `AXIS`).
- Banks + sender rules are seeded from `txn_parser`'s `builtInBanks` — the parser is the single source of truth for bank definitions.

## Adding / fixing a bank message format (parser session)
1. Mask the message first: account/card digits beyond last 4, names of real people, phone numbers. Fixtures are committed to git.
2. Add a case to `packages/txn_parser/test/fixtures/<bank>.json` with `expected` fields (only listed keys are asserted). Run `dart test` — it should fail.
3. Add or fix a `ParserTemplate` in `lib/src/banks/<bank>.dart`. Patterns match whitespace-collapsed, HTML-stripped text, case-insensitive. Use `rx()` tokens `{amt}`, `{rs}`. Named groups: amount, direction, type, last4, payee, ref, date, balance, dueDate, mandateRef, currency. Fixed values go in `defaults` (`direction`, `txnType`).
4. New bank: new `BankDefinition` file + register in `registry.dart` + new fixture file. Sender IDs are the header core (`AXISBK` matches `AX-AXISBK-S`); email senders are domains or full addresses.
5. Keep all tests green; never loosen a test to make a template pass.

## Status
- Phase 1 done (setup, encrypted DB, parser + tests). Bank templates are synthetic until real samples replace them.
- Design done ("Note Inks" direction: amounts tinted by RBI banknote band; see DESIGN.md). Flutter must use Archivo wdth≈112 + tabular figures for amounts/headings.
- Phase 2 code done (native SMS capture + headless worker, ingestion pipeline, Transactions/detail/onboarding UI); awaiting on-device test. Next: Phase 3 (review queue + learned templates + category rules).
- Phase 2b done: self-transfer linking (`TransferLinker`, schema v2). Phase 2c done: computed account balances + Accounts screen, owner-added transfer side (schema v3), account merge (v4).
- Phase 3 code done: review queue, mark-and-learn (user templates in `parser_templates`), merchant category rules, payee rename, learned formats screen.
- Phase 4 code done: subscription detection (`lib/data/subscriptions/`), AutoPay matching, reminders.
- Phase 5 done: email (IMAP app password + Gmail sign-in, `lib/data/email/`), SMS/email dedup, hourly sync, Add payment, theme setting, app icon (`tool/app_icon.py`).
- Phase 6 code done: summary, app lock (`lib/app/app_lock.dart`), encrypted Drive backup + export/import (`lib/data/backup/`); awaiting device test.
- Later ideas: encrypted multi-device sync (schema already sync-ready), other currencies.
