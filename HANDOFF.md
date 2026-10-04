# Handoff — k

Read this first in a new session, then `CLAUDE.md` (rules, layout, commands), `PRODUCT.md` (product truth) and `DESIGN.md` (design system). Updated 2026-10-04.

## What k is
Personal, sideloaded Android app (Flutter + native Kotlin for SMS) that logs payments by parsing bank SMS and bank alert emails (Axis, Kotak, BOB), dedups SMS+email, categorizes, detects subscriptions. All data on-device, encrypted DB. Owner works in two sessions: **main** (design + app phases) and **parser** (`packages/txn_parser/` only).

## Decisions already made (don't re-ask)
- Flutter + flutter_bloc + get_it; drift + SQLite3MultipleCiphers via `sqlite3` build hooks (no sqlcipher_flutter_libs); workmanager; native Kotlin only for SMS capture; minSdk 26; device Nothing Phone 2.
- Money = int minor units + currency (INR now, extensible). Enums stored by name.
- Schema is sync-ready (UUIDv7 ids, updatedAt, deletedAt soft delete) for possible future encrypted Firebase sync — not building sync now.
- Email: Gmail API OAuth (consent screen "In production", unverified, personal use) + IMAP app-password fallback. Drive backup: daily, encrypted JSON, `drive.file`, keep 7.
- Defaults: 10-min dedup window (cross-channel only), ±10% subscription tolerance, reminders 3 days before, email sync hourly.
- Implement directly, no diffs (owner preference for this project). Confirm destructive actions.
- Design direction "Note Inks": amounts tinted by RBI banknote colour per amount band; **no note/cash wording in UI** (most payments are UPI); guilloche rosettes allowed only in the six places listed in DESIGN.md.

## State
| Area | Status |
|---|---|
| Phase 1: setup, encrypted DB (15 tables, seeds), parser + tests | Done. `flutter test` 8 pass; `dart test` in txn_parser 97 pass; analyze clean |
| Parser real samples (parser session) | In progress. Real formats added for Axis/Kotak/BOB UPI, Axis NEFT, Kotak debit card + AutoPay; real sender headers; BOB has no email alerts (emailSenders empty); Axis emails also from `axis.bank.in` |
| Design | Done. `design/k.pen` (Pencil, encrypted — open only via Pencil MCP), exports in `design/screens/` (00 app icon … 08 light), `DESIGN.md` + `.impeccable/design.json` tokens |
| Phase 2: native SMS ingestion + Transactions list | **Next** |
| Phases 3–6 | Not started: 3 review queue + categorization rules, 4 subscriptions + reminders, 5 Gmail + dedup, 6 summary + backup/export + app lock |

## Next step: Phase 2 plan (agreed architecture)
1. Android: `RECEIVE_SMS`, `READ_SMS` in manifest. Kotlin `SmsReceiver` (SMS_RECEIVED) → `PendingSmsQueue` (app-private) → if app alive push via `EventChannel`, else enqueue expedited `SmsProcessWorker` that boots a headless FlutterEngine on Dart entrypoint `smsBackgroundMain`. `SmsInboxReader` (ContentResolver) for first-run history (user-chosen date range) and catch-up scan by last SMS `_id` cursor on every app open/periodic run. Store `sim_slot`.
2. Dart: `SmsBridge` (MethodChannel/EventChannel), ingestion pipeline: raw_messages (sha256 contentHash idempotency) → `ParserEngine` (sender rules from DB) → account auto-create (bank,last4) → merchant normalize → transaction; unparsed → status needsReview.
3. DAOs/repositories for raw_messages, transactions, accounts, merchants.
4. UI per DESIGN.md: theme (dark primary, light twins; Archivo wdth≈112 + tabular figures for amounts/headings, Roboto body), components (Note Chip, Txn Row, Bottom Nav M3, Filter Chip, Month Note Panel with rosette painter + denomination ribbon), Transactions screen (filters, review banner, day groups, upcoming), Transaction detail with raw message sources.
5. Permission onboarding incl. Android 13+ "restricted settings" for sideloaded SMS apps (App info → ⋮ → Allow restricted settings), battery "Unrestricted" on Nothing OS.
6. List permissions + gotchas for the owner, stop for on-device testing.

## Gotchas learned
- Pencil MCP: screenshots render lazily — first capture can be blank/stale; re-capture or use `export_nodes`. Replacing variables with `SetVariables(..., true)` bakes refs to hex — never replace-all variables. Reusable components don't inherit parent theme; tokens are dark values plus `*-light` twins (light screen = swap refs).
- `head` in this shell is shadowed by a Perl LWP tool — use `sed -n 1,Np`.
- zsh doesn't word-split `set -- $var`; use python for batch renames.
- Two sessions share the tree: `git add <own paths>` only, never `-A`.
- `.impeccable/review/` is gitignored scratch; `.impeccable/questions/*.state.json` may show as modified — harmless.

## Open items
- Light-theme inks ink-10/20/200 sit close; verify on device.
- Not yet designed: SMS-permission-revoked and Gmail-sync-failed states (add in phases 2 and 5).
- Design review: second-round fixes self-verified, not re-scored by reviewer.
