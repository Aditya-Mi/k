# Handoff — k

Read this first in a new session, then `CLAUDE.md` (rules, layout, commands), `PRODUCT.md` (product truth) and `DESIGN.md` (design system). Updated 2026-10-05 (Phases 2–5 done and device-tested; Phase 6 code done: app lock, Drive backup, export/import — awaiting device test; Cash account added; same-name payees merge). Schema v7.

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
| Phase 2b: self-transfer linking | **Done.** `flutter test` 28 pass. Owner tested Phase 2 on device: SMS capture works |
| Phase 2c: account balances + owner-added transfer side + account merge | **Done.** `flutter test` 33 pass |
| Phase 3: review queue, save & learn, category rules | **Done.** Owner tested on device (fixes: dialog crash, slash words, learned formats screen) |
| Phase 4: subscriptions + reminders | **Done** (code). Owner can't set up the device checks; don't ask again |
| Phase 5: email + dedup | **Done.** Device-tested: Gmail sign-in (Testing mode, owner is a test user), email ingest, SMS+email merge, Save & learn on email, Add payment. Later checks: hourly background sync with app swiped away; 7-day Gmail expiry → re-sign-in. Owner keeps an app-password inbox on the same address as backup (content hash stops double logging) |
| Phase 6 | **Code done, awaiting device test.** Summary (05), app lock (07/07b), Drive backup + export + import/restore (06e–06h). `flutter test` 79 pass, debug APK builds |

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
- `lib/ui/` — theme tokens (`KColors` ThemeExtension, `KText` Archivo wdth 112 + tnum via bundled variable font `assets/fonts/Archivo.ttf`), `Bands`, formatters (en_IN grouping). Widgets: NoteChip/LargeNoteChip, Rosette (house + per-name seal generator, `progress` ready for the drawn moment), MonthNotePanel + SpendRibbon, TxnRow/UpcomingRow, KFilterChip, NoticeBanner, DayHeader, FieldRow, RawMessageCard (MERGED stamp), EmptyState. Screens: Onboarding (SMS incl. restricted-settings help, battery, history: None / This month (default, from the 1st) / 90 days / Pick date), HomeShell (M3 nav, neutral review badge; Review/Subscriptions/Summary are placeholders), Transactions (month panel, filters month/accounts/category/direction, search, SMS-off banner, review banner, pinned section head, upcoming, day groups), Txn detail (watermark rosette, category picker, note, not-a-transaction/delete with confirm), Settings (SMS/battery status, last checked, check inbox now, import older messages from a picked date — dedup makes re-import safe).

## Phase 2b: self transfers
- Schema v2: `transactions.transfer_id` (shared by both sides; alone when the other account isn't tracked) + `auto_transfer_off` (user unlinked → never auto-link again). Migration in `app_database.dart` `onUpgrade`.
- `lib/data/ingest/transfer_linker.dart`: auto rule = debit + credit, same amount/currency, different own accounts, within 30 min (owner-approved), closest wins. Runs per ingested txn and as `autoLinkAll()` backfill on app start. Linked rows get category `cat_transfers` unless user-edited; unlink re-resolves category.
- UI: row title "Self transfer", meta "Axis ··0640 → Kotak ··4410 · time", swap icon; excluded from month spent/in/spend count and day "out" totals. Detail: "Self transfer" field, "Not a self transfer" (unlink) or "Mark as self transfer" (pick same-amount opposite row on another account within ±3 days, or "account not in k").

## Phase 2c: balances + missing transfer side
- Schema v3: `transactions.origin` (`message`|`user`), `accounts.manual_balance_minor/_at`. Migration also folds "no last4" accounts into the bank's only savings/current account (BOB UPI credits name no account).
- Ingestion: alert without last4 → the bank's single savings/current account if there is exactly one.
- Balances are computed, not stored (`computeBalance` in `ledger_models.dart`): newest bank-reported balance (txn `balanceMinor`) or the owner's manual figure if newer, plus later credits − debits (marked estimated). Card = available limit. Accounts screen (wallet icon on home): balance + source, Rename, Set balance/limit.
- "Mark as self transfer" can add the missing side on another tracked account (`origin = user`, "added by you"; detail shows the other side's message). A late real SMS (same account/amount/direction within ±3 days) becomes that row. Unlink soft-deletes an added side.
- Fixed: detail screen now uses `switchMap` (edits refresh live). Rosette now uses exact design geometry minus the 5-lobe core (owner request).

## Account merge (schema v4)
- `accounts.merged_into_id`: folded account stays (so its last4 still resolves) but is hidden; target lists "Includes card ··4192".
- Debit card alerts log on the bank's sole savings/current account automatically (card account created already merged). v4 migration folds existing auto-created debit card accounts the same way.
- Accounts screen → "Merge into another account" (confirm; no unmerge yet).

## Phase 3: review + learning
- `IngestionService` refactored: shared `_log` (txn/upcoming creation), `parseRaw`, `logReviewed`, `reprocessReview` (re-reads the queue after a format is learned), `markNotTransaction`.
- `lib/data/review/field_marks.dart`: `MarkField` (account, direction, amount, payee, ref, date, balance), `trimToField` (selection → what the field holds, e.g. XX1234 → 1234), `prefillMarks` (places parser guesses in the text). Done app-side because the parser package belongs to the parser session.
- `lib/data/review/review_service.dart`: queue stream (re-parses each item for guess + reason), `fieldsOf(draft)`, `save` = optional learn (TemplateGenerator → verified by a throwaway ParserEngine reading the sample back: amount, direction, account; tries capturing the direction word first, else fixed direction default) → insert `parser_templates` (priority 10) → log txn → merchant rule if a category was picked → `reprocessReview`.
- UI: Review tab (`review_queue_screen.dart`, empty state 03c), editor (`review_editor_screen.dart` + cubit; `message_marks.dart` renders marks with captions; long-press a word → sheet to grow/shrink the selection and pick a field; tap a mark to change/remove), learned overlay (`learned_overlay.dart`, rosette draws 600ms staggered 40ms/path, hold, fade; reduce-motion shows it drawn).
- Category rules: detail category sheet has "Use for all <payee>" (default on) → `category_rules` merchant rule (`mr_<key>`, origin user) + re-files that merchant's non-hand-edited, non-transfer payments; ingestion cache invalidated via `LedgerRepository.onRulesChanged`. Payee rename on detail (tap the name) renames the merchant everywhere.

## Phase 3 device-test fixes
- Text dialogs crashed on close (`_dependents.isEmpty`): controller was disposed while the dialog animated out. All prompts now use `promptText` (`lib/ui/widgets/text_prompt.dart`, dialog owns its controller).
- Review: slash-joined words (`NEFT/IN827459235/NAME`) are pressable part by part; ref trim keeps the longest digit-bearing run.
- Learned formats screen (Settings → Message formats): sample message with what the format reads, uses count, pause (`enabled`), forget (soft delete). Service `lib/data/review/learned_formats.dart`.
- Right-overflow while growing a selection in Review was the slash-split Row; fixed (Wrap).

## Phase 4: subscriptions + reminders
- Design first (new rule): `04b-subscription-detail`, `04c-subscriptions-empty`, `03e-learned-formats` added to `design/k.pen` + `design/screens/`.
- `lib/data/subscriptions/recurrence.dart` (pure): `detectRecurrence` — only charges within tolerance of the newest amount; walk back by cycle windows (monthly 26–35d, quarterly 84–98, half-yearly 174–190, yearly 355–375); a similar charge inside a cycle ends the run; min run 3 monthly / 2 otherwise. `nextCharge` keeps day-of-month (clamped). `monthlyMinor` for totals.
- `SubscriptionService.refresh()` (after every SMS drain/catch-up in `SmsController`): expire AutoPay alerts >3 days past due → match unlinked debits of tracked merchants (within tolerance anywhere after last charge + half a cycle, or any price within ±7 days of the expected day = price change) → attach pending AutoPay alerts (sets next charge; suggests a plan if none) → detect new runs (merchant with no plan; dismissed blocks forever; stopped blocks only charges it already covered; newest charge must be within 1.5 cycles).
- Suggested plans already link their charges (`transactions.subscription_id`); "Not a subscription" unlinks; "Stop tracking" keeps links. `priceChanged` + `lastAmountMinor` = "was" price, cleared by the next same-price charge or a manual amount edit.
- Reminders: `lib/app/reminder_scheduler.dart` (flutter_local_notifications + timezone, inexact alarms, 09:00 N days before; rebuilt from scratch on every change; 0 = off; per-plan override, global default `subscriptions.reminderDays`). Manifest: POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED + plugin receivers; desugaring on. Notification permission asked on first "Track it". Icon `drawable/ic_stat_k`.
- UI: Subscriptions tab (totals, suggestion cards, "Reminds N days before" → global sheet, rows with seal / price-up / unused / cycle bar), detail (rename, amount, repeats, next charge date via the cycle line, category, remind me, not using it, charges list, stop tracking). `CategoryButton` moved to `widgets/common.dart`.

- Track from a payment (design `02c`): txn detail → "Track as subscription" sheet (repeats + next charge) → `SubscriptionService.trackFromTransaction` (reuses an open plan for the merchant, else a `manual` one). Linked txns show a "Subscription" field that opens the plan.
- Notifications (`lib/app/notifications.dart`, `KNotifications`, replaces ReminderScheduler): subscription reminders (scheduled), payment logged (one per txn) and needs review (one running notice, id 1) — live alerts only after a receiver-queue drain (`SmsSync.onLive`, both isolates; background engine inits the plugin), never catch-up/history, not while the app is visible; review notice cleared on resume. Private visibility (hidden on lock screen). Toggles `device.notify.payments` / `device.notify.review` (default on). Settings → Notifications section (design 06 updated; `notification_settings.dart` has `SettingsItem`/`SettingsHead` in the 06 style — the rest of Settings is still the Phase 2 layout).
- Add subscription by hand (design `04d`, "+" on the Subscriptions tab and in its empty state): `addManual` creates an active plan with no merchant; `_matchFirstCharge` links the first debit within ±7 days of the next charge, within tolerance, whose payee shares a 3+ char word with the name, then sets the plan's merchant.
- Review queue is re-read on every app start (`reprocessReview`), so parser updates clear waiting items without a reinstall.

### For the parser session
- AutoPay / e-mandate templates must capture `payee` (merchant) and `dueDate`; alerts without a payee can't attach to a subscription.
- Missing Kotak format (upcoming AutoPay, kind mandate): `AUTOPAY of Rs.195.00 to APPLE MEDIA SERVICES will be debited on 29 Sep 2026. Please ensure sufficient balance in account -Kotak` (no account digits). Executed form already parses (`kotak_sms_autopay_done`).

## Phase 5: email + dedup
- Dedup (`IngestionService._crossChannelTwin`): same account, amount, direction within `dedup.windowMinutes` (10) and the existing row has no source from this channel → this message becomes a second source (`IngestOutcome.merged`), filling missing ref/balance/payee. Same-channel repeats never merge.
- `lib/data/email/`: `EmailSource` interface, `ImapSource` (enough_mail, TLS 993, All Mail via \All flag else INBOX, `UID n:*` / `SINCE` + `OR FROM` bank sender rules, cursor `uidValidity:lastUid`, BODY.PEEK so mail stays unread), `EmailSync` (accounts in `email_accounts`, secrets in secure storage `email.secret.<id>`, `device.email.<id>.since/error`, serialized `syncAll`, `syncIfStale`, `onLive` → notifications).
- Background: native `email/EmailSyncWorker` (periodic 60 min, network) → headless `emailBackgroundMain`; scheduled via `k/sms` `scheduleEmailSync` on connect/disconnect and every app refresh; foreground top-up when >30 min stale.
- UI: Settings → Email (inboxes, failed state in alert colour, sheet: new app password / check now / disconnect), `ConnectInboxScreen` (06b; Google option disabled until `googleReady`), `AppPasswordScreen` (06c). Designs 06b/06c/06d in k.pen.
- Main manifest now declares INTERNET (release builds).
- Gmail sign-in: Cloud project "k" set up by the owner (External, In production, unverified; scopes `gmail.readonly` + `drive.file`). `lib/data/email/google_auth.dart` holds the Web client ID (`serverClientId`; the Android client is matched by package + debug SHA-1, nothing from it in the app). `signIn()` = `authenticate` + `authorizeScopes`; `token(email)` calls the platform interface directly with the account email and no prompt, so it works in the headless worker (plugin's authorize uses the app context). `GmailSource` (`gmail_source.dart`): REST `messages?q=from:(a OR b) after:<sec>` → `format=raw` → enough_mail; cursor `ms:<newest internalDate>`, re-looks 1h back (content hash drops repeats); 401 → clear token, retry once. MIME → `FetchedEmail` shared in `mime_email.dart`. `EmailSync.addGoogle`; disconnecting the last Google inbox revokes access. Settings sheet: "Sign in with Google again" when a Gmail inbox fails.

## Branding + theme
- Launcher icon: adaptive, bg `#101114` (`values/colors.xml`), foreground is a VectorDrawable generated by `python3 tool/app_icon.py` (rosette math as `rosette.dart` + Archivo Bold "k" outline from the bundled font, 0.6dp strokes, inside the 66dp safe circle) — vector so it stays sharp; PNG export was blurry. Design: `oIgGv` in `design/k.pen` (`qrR0K` = foreground-layer reference). Legacy `mipmap-*/ic_launcher.png` only matter below API 26 (unused). Android 12+ splash bg per theme in `values-v31` / `values-night-v31`.
- Settings → Appearance → Theme (System / Light / Dark), `device.theme`, read before first frame in `main.dart`. Design 06 updated.
- Don't upload a logo in Google Cloud Branding: a logo forces brand verification.

## Add payment + email review fixes (2026-10-05)
- Add payment (design `09-add-payment`, "+" on the Transactions app bar): Paid/Received, amount, payee, account (or "Cash or not in k" = no account), category, when, note → `IngestionService.addManual` (`origin = user`). A late SMS/email for the same account/amount/direction within ±3 days becomes that row (`_ownerAddedRow`) and now keeps the owner's payee (bank's "RAZORPAY" doesn't overwrite "Hostinger").
- Bank email that no format reads and with no amount anywhere → `nonTransaction` ("email without an amount"), never Review; also applied to waiting items by `reprocessReview` on app start. SMS unaffected.
- Detail message cards show emails via `readableEmail` (`lib/data/email/readable_text.dart`: HTML → lines, entities, padding collapsed). Stored body untouched.
- Owner saved 13 email reviews with Save & learn (learned formats in `parser_templates`); they merged with their SMS.

### For the parser session (email) — done by the parser session
- Axis e-statement mail (`statements@axis.bank.in`, subject "AXIS BANK : Statement for <Month> <Year>") → add an `ignore` template (app now skips it anyway since it has no amount).
- `axis_email_txn_summary` takes the amount + direction from the subject only. The body also has `Amount Debited: INR 25.00` / `Account Number: XX0640`; a body-only fallback would survive subject changes.
- Ask the owner for the 13 learned email formats (Settings → Message formats shows each sample) to turn into built-ins + fixtures.

## Summary, Settings, ATM category (2026-10-05)
- Summary tab built (design 05 redone with impeccable): month panel ("So far this month", "₹X left"), 6-month trend (closed months outlined, open month filled), Day by day calendar (cells inked by the day's spend band; tap → day's payments), categories, top payees, spend sizes. Data: `lib/data/summary/month_report.dart` (pure, tested). Owner checked on device.
- Settings rebuilt to design 06: Accounts, Banks (`BankRepository`, add sender → parser cache invalidated), Email, Sync (SMS, battery, check now, read past SMS, email hourly, merge window `dedup.windowMinutes`), Notifications, Appearance, Message formats. Backup + App lock wait for Phase 6.
- Schema v5: "Cash" category → "ATM withdrawal" (id `cat_cash` kept); `CategoryResolver` files `TxnType.atm` there first; migration re-files unedited ATM rows.

## Phase 6: app lock + backup (2026-10-05)
**App lock** (`lib/app/app_lock.dart`, `lib/ui/screens/lock/lock_screen.dart`, Settings → Privacy): `local_auth` BiometricPrompt (fingerprint or screen lock). `MainActivity` is now `FlutterFragmentActivity`; manifest has USE_BIOMETRIC. Locks on cold start and after ≥1 min away (so share sheets / Google sign-in / file dialogs don't lock); lifecycle events during the prompt are ignored (PIN fallback is its own activity). Overlay sits in `MaterialApp.builder` above the navigator. Unlock → rosette draws (neutral) → hold → fade into home. Turning on asks the prompt once; a phone with no screen lock left opens instead of being stuck. `device.appLock`. LaunchTheme is still not AppCompat (local_auth wants it only for Android ≤8).

**Backup** (`lib/data/backup/`, `lib/ui/screens/backup/`, Settings → Backup):
- `.kbackup` (`backup_file.dart`): JSON `{header, nonce, data}`; header = format/version, meta (createdAt, schema, counts — readable before the passphrase for the restore screen) and Argon2id params+salt (19 MiB, t=2, p=1, in an isolate); data = AES-256-GCM over gzipped snapshot JSON, header bound as AAD.
- Passphrase (owner's choice) never stored: derived key + KDF params in secure storage (`backup.key`, `backup.kdf`), so the worker backs up unattended and a file with the same salt restores without asking. Restore with a passphrase adopts that key. Changing it = new salt; older backups need the old one.
- `snapshot.dart`: every table's raw rows (`device.*` settings excluded both ways); restore = one transaction, deferred FKs, wipe + insert columns this version knows (older backups restore; newer refused), then `notifyUpdates` all tables; `onRestored` in di re-seeds, invalidates ingestion, refreshes subscriptions, reprocesses review.
- Drive (`drive_client.dart`): REST v3, `drive.file`, folder "k backups" (id cached `device.backup.folderId`), resumable upload, appProperties `payments`, keep 7. `GoogleAuth.signIn/token` take a scope; backup account `device.backup.account` (null = off). Removing the last Gmail inbox no longer revokes Google while backup is on.
- Daily: native `backup/BackupWorker` (periodic 1 day, first run aimed at 03:00, KEEP, network + battery not low) → `backupBackgroundMain` → `runIfDue` (20 h gap). App refresh re-schedules and catches up if >36 h. `work/HeadlessWorker` is the shared headless-engine base (EmailSyncWorker now extends it).
- Export sheet: CSV (`csv_export.dart`, signed rupees, formula-guarded cells, not encrypted) or backup file → `file_picker` save dialog. Import a file / tap a Drive copy → Restore screen (confirm dialog; replaces everything). New phone: Backup → "Find backups on Drive" signs in first.

Phase 6 device checks:
1. Settings → Privacy → App lock on (prompt once). Swipe away + reopen → lock screen + prompt; cancel → Unlock button; success → rosette draws, fades into home. Leave <1 min (e.g. Export save dialog) → no lock; >1 min → lock.
2. Settings → Backup switch → passphrase → Google account (Drive consent; unverified-app warning again) → "Backed up to Drive"; Drive shows "k backups/k-…kbackup". Backup screen lists it.
3. Next morning: Last backup ~03:xx (worker). Battery saver may delay it.
4. Export CSV opens in Sheets; Export backup file → Import it (should say "Opens with your current backup passphrase") → Restore → data back.
5. Wrong passphrase on a file from another salt → "That passphrase doesn't open this backup".

## Cash in hand (schema v6, 2026-10-05)
Owner's rule: an ATM withdrawal counts as spent (as before) and adds to cash; a cash payment logged by hand lowers cash but is **not** counted as spent again (₹11k withdrawn for rent + ₹11k cash rent logged = ₹11k spent, not ₹22k).
- Seeded pseudo bank `CASH` + account `acc_cash` (`AccountType.cash`, ids in `seed_data.dart`); v6 migration just re-runs the idempotent seeder. Hidden from Settings → Banks, never a merge source/target or self-transfer side (auto-link, candidates, "add the other side").
- `computeCashBalance`: owner's counted figure (Accounts → Set balance) or 0, plus later ATM debits on any other account (an ATM credit/deposit subtracts), plus cash credits, minus cash debits.
- `TxnView.countsInTotals` (= not a transfer, not cash) drives month panel, Summary report and day "out" totals. So cash payments don't show in Summary categories; the withdrawal stays under "ATM withdrawal".
- Add payment: "Cash" is an account choice (lowers cash), "Not in k" replaces "Cash or not in k". Txn row shows a cash icon; detail says "from cash, counted at the ATM".
- Designs: `10-accounts` (Cash in hand row), `09b-add-payment-account-sheet` (Cash / Not in k), Cash row in `06-settings`.

## Payee merge (schema v7, 2026-10-05)
Bug: renaming payees to the same name ("Zepto") only changed display names; separate merchant rows stayed, so Summary top payees split the amount (grouped by merchantId), and subscriptions/"use for all" rules saw separate payees too.
- `merchants.merged_into_id`. `AppDatabase.mergeMerchant(source, target)`: transactions, subscriptions, upcoming charges, aliases move; the source's merchant category rule moves to the target unless it has one; source row stays as a pointer. Ingestion `_merchantFor` follows the pointer.
- `LedgerRepository.renameMerchant` merges every other live merchant with the same name (case-insensitive) into the renamed one; detail shows "Now one payee with X".
- v7 migration `mergeSameNameMerchants()` folds existing duplicates (most payments keeps its row). No unmerge yet.

## Next step: Phase 6 device test
Google Cloud project stays in **Testing** (owner's choice: production needs homepage + privacy policy URLs); Gmail grant expires every 7 days.
Phase 5 checks: Settings → Email → Connect → Sign in with Google (unverified warning → Advanced → Go to k; allow Gmail read) → bank mail imports; a payment with SMS + email shows once with two sources; app password path; background hourly sync after swiping the app away.


## Earlier device checks (Phase 2/3)
1. Review tab lists unread messages with a guessed amount and reason.
2. Open one: marks prefilled; long-press words to fix; Save & learn → overlay; similar waiting messages clear.
3. Learned formats live in `parser_templates`; send the parser session the sample texts so built-ins can absorb them later.
4. Detail: change category with "Use for all" on → other payments to that payee re-file; rename a payee.

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
- Balance after a manual set is "set by you", then estimated by later payments; negative balances can't be entered (overdraft) — add if needed.
- Phase 3 gaps: learning only makes transaction formats (not mandate/ignore); no undo for "Not a transaction" in review.
- Phase 2 shortcuts: section head shows the whole list's date span (not the span in view); upcoming charges have no account last4 (not stored on `upcoming_charges`); credits with no keyword stay Uncategorized; merchant names from VPAs can be ugly ("Zeptonowcashfree") until Phase 3 renames/merges.
- Widget tests render via `tester.runAsync` + drift streams hang on teardown — screenshot harness was deleted; if adding widget tests, close cubits/DB inside runAsync.
- Light-theme inks ink-10/20/200 sit close; verify on device.
- Not yet designed: SMS-permission-revoked and Gmail-sync-failed states (add in phases 2 and 5).
- Design review: second-round fixes self-verified, not re-scored by reviewer.
