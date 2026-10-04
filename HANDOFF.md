# Handoff — k

Read this first in a new session, then `CLAUDE.md` (rules, layout, commands), `PRODUCT.md` (product truth) and `DESIGN.md` (design system). Updated 2026-10-04 (Phase 2 code done).

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
| Phase 1: setup, encrypted DB (15 tables, seeds), parser + tests | Done |
| Parser real samples (parser session) | In progress. Real formats for Axis/Kotak/BOB UPI, Axis NEFT, Kotak debit card + AutoPay |
| Design | Done. `design/k.pen`, exports in `design/screens/`, `DESIGN.md` |
| Phase 2: native SMS ingestion + Transactions list | **Code done, awaiting on-device test.** `flutter test` 21 pass, analyze clean, debug APK builds |
| Phases 3–6 | Not started: 3 review queue + categorization rules, 4 subscriptions + reminders, 5 Gmail + dedup, 6 summary + backup/export + app lock |

## Phase 2: what was built
**Android** (`android/app/src/main/kotlin/dev/adityamittal/k/sms/`)
- `SmsReceiver` (SMS_RECEIVED, priority 999): joins multipart, keeps only alphanumeric senders (`SenderFilter` — personal numbers never queued), writes `PendingSmsQueue` (JSON in `noBackupFilesDir`, removed only on Dart ack). If the UI is listening (`SmsEventHub`, EventChannel `k/sms_events`) it pings; else enqueues `SmsProcessWorker`.
- `SmsProcessWorker`: expedited unique work (APPEND_OR_REPLACE), boots headless FlutterEngine on Dart `smsBackgroundMain` (in `lib/main.dart`), waits for `backgroundDone` (60s timeout, retry ×5; leftovers drain on next app open).
- `SmsInboxReader`: pages `content://sms/inbox` by `_id`, uses `date_sent` (service-centre time = what the receiver sees) so live + inbox copies hash the same.
- `SmsChannel` (MethodChannel `k/sms`): drainPending, ackPending, readInbox, maxInboxId, backgroundDone. Manifest: RECEIVE_SMS, READ_SMS, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, FGS dataSync (expedited work on <12). Dep: `androidx.work:work-runtime-ktx`.

**Dart**
- `lib/platform/sms_bridge.dart` — channel wrapper.
- `lib/data/ingest/ingestion_service.dart` — contentHash + 5-min same-sender/body dup check → `ParserEngine` (sender rules + user templates from DB) → raw_messages (status parsed/needsReview/nonTransaction; notBank is dropped, not stored) → account auto-create by (bank,last4) with type heuristic (limit/"credit card" → creditCard, "debit card" → debitCard) → merchant via alias/normalizedKey → `CategoryResolver` (merchant rules, then longest keyword on word boundaries, VPA substring for keywords ≥5 chars) → transaction + source. Mandate alerts → `upcoming_charges` (pending).
- `lib/data/ingest/sms_sync.dart` — serialized drain / catch-up (cursor `device.sms.inboxCursor`) / first-run history import.
- `lib/data/repositories/` — `LedgerRepository` (filtered txn stream with source count, detail with raw messages, accounts, categories, upcoming, review count, set category/note, soft-remove), `SettingsRepository` (device.* keys are device-local, exclude from future sync).
- `lib/app/` — `KApp` (onboarding gate, light/dark themes), `SmsController` (drain on events; drain + catch-up on start/resume; exposes SMS permission).
- `lib/ui/` — theme tokens (`KColors` ThemeExtension, `KText` Archivo wdth 112 + tnum via bundled variable font `assets/fonts/Archivo.ttf`), `Bands`, formatters (en_IN grouping). Widgets: NoteChip/LargeNoteChip, Rosette (house + per-name seal generator, `progress` ready for the drawn moment), MonthNotePanel + SpendRibbon, TxnRow/UpcomingRow, KFilterChip, NoticeBanner, DayHeader, FieldRow, RawMessageCard (MERGED stamp), EmptyState. Screens: Onboarding (SMS incl. restricted-settings help, battery, history range), HomeShell (M3 nav, neutral review badge; Review/Subscriptions/Summary are placeholders), Transactions (month panel, filters month/accounts/category/direction, search, SMS-off banner, review banner, pinned section head, upcoming, day groups), Txn detail (watermark rosette, category picker, note, not-a-transaction/delete with confirm), Settings (SMS/battery status, last checked, check inbox now).

## Next step: on-device test of Phase 2, then Phase 3
Owner to run `flutter run` (or `adb install`) on the Nothing Phone 2 and check:
1. Onboarding: SMS Allow. If sideloaded via file manager/browser, Android 13+ blocks it → App info → ⋮ → Allow restricted settings. `flutter run`/`adb install` installs are not restricted.
2. Battery Allow, plus Nothing OS App info → Battery → Unrestricted.
3. History import count looks right; review count = formats the parser misses (feed those to the parser session).
4. Live: pay something with app open → row appears; force-stop is NOT a fair test (Android blocks broadcasts to force-stopped apps); swipe app away → pay → row appears on next open or within seconds (worker).
5. Same SMS must not appear twice (live + catch-up) — if it does, check `date_sent` vs receiver timestamp on this OEM.
6. SIM slot shows in raw message card ("SIM 1/2") — Nothing may not put slot extras in the intent.
Then Phase 3: review queue + fix-by-selection + learned templates + category rules (design: `03a–03d`).

## Gotchas learned
- Pencil MCP: screenshots render lazily — first capture can be blank/stale; re-capture or use `export_nodes`. Replacing variables with `SetVariables(..., true)` bakes refs to hex — never replace-all variables. Reusable components don't inherit parent theme; tokens are dark values plus `*-light` twins (light screen = swap refs).
- `head` in this shell is shadowed by a Perl LWP tool — use `sed -n 1,Np`.
- zsh doesn't word-split `set -- $var`; use python for batch renames.
- Two sessions share the tree: `git add <own paths>` only, never `-A`.
- Pinned `SliverPersistentHeader` child must fill its extent (alignment), or geometry asserts.
- `timeout` is not installed in this shell; long flutter runs → Bash `run_in_background`.
- `.impeccable/review/` is gitignored scratch; `.impeccable/questions/*.state.json` may show as modified — harmless.

## Open items
- Phase 2 shortcuts: section head shows the whole list's date span (not the span in view); upcoming charges have no account last4 (not stored on `upcoming_charges`); credits with no keyword stay Uncategorized; merchant names from VPAs can be ugly ("Zeptonowcashfree") until Phase 3 renames/merges.
- Widget tests render via `tester.runAsync` + drift streams hang on teardown — screenshot harness was deleted; if adding widget tests, close cubits/DB inside runAsync.
- Light-theme inks ink-10/20/200 sit close; verify on device.
- Not yet designed: SMS-permission-revoked and Gmail-sync-failed states (add in phases 2 and 5).
- Design review: second-round fixes self-verified, not re-scored by reviewer.
