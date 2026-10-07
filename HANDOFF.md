# Handoff — k

Read this first in a new session, then `CLAUDE.md` (rules, layout, commands), `PRODUCT.md` (product truth) and `DESIGN.md` (design system). Updated 2026-10-05 (Phases 2–5 done and device-tested; Phase 6 code done: app lock, Drive backup, export/import — awaiting device test; Cash account added; same-name payees merge; custom categories; unknown-sender learning, AutoPay/skip learning, review undo, sync-problem banners, overdrawn balances). Schema v9.

> **Next: one commit + release (motion and polish done); see "NEXT SESSION" below. Working tree has uncommitted work since `ca4de66`.**

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
| Phase 6 | **Device-tested on release 1.0.1** (2026-10-05): app lock, Drive backup (Back up now), import/restore. Not yet: overnight backup worker, wrong-passphrase, CSV export. Summary (05), app lock (07/07b), Drive backup + export + import/restore (06e–06h) |

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
- UI: row title "Self transfer", meta "Axis ··1111 → Kotak ··5555 · time", swap icon; excluded from month spent/in/spend count and day "out" totals. Detail: "Self transfer" field, "Not a self transfer" (unlink) or "Mark as self transfer" (pick same-amount opposite row on another account within ±3 days, or "account not in k").

## Phase 2c: balances + missing transfer side
- Schema v3: `transactions.origin` (`message`|`user`), `accounts.manual_balance_minor/_at`. Migration also folds "no last4" accounts into the bank's only savings/current account (BOB UPI credits name no account).
- Ingestion: alert without last4 → the bank's single savings/current account if there is exactly one.
- Balances are computed, not stored (`computeBalance` in `ledger_models.dart`): newest bank-reported balance (txn `balanceMinor`) or the owner's manual figure if newer, plus later credits − debits (marked estimated). Card = available limit. Accounts screen (wallet icon on home): balance + source, Rename, Set balance/limit.
- "Mark as self transfer" can add the missing side on another tracked account (`origin = user`, "added by you"; detail shows the other side's message). A late real SMS (same account/amount/direction within ±3 days) becomes that row. Unlink soft-deletes an added side.
- Fixed: detail screen now uses `switchMap` (edits refresh live). Rosette now uses exact design geometry minus the 5-lobe core (owner request).

## Account merge (schema v4)
- `accounts.merged_into_id`: folded account stays (so its last4 still resolves) but is hidden; target lists "Includes card ··4444".
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
- Review: slash-joined words (`NEFT/IN26000000000001/NAME`) are pressable part by part; ref trim keeps the longest digit-bearing run.
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
- `axis_email_txn_summary` takes the amount + direction from the subject only. The body also has `Amount Debited: INR 25.00` / `Account Number: XX1111`; a body-only fallback would survive subject changes.
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
4. ✓ Import of a backup file restored on 1.0.1 (2026-10-05). Export CSV opens in Sheets; Export backup file → Import it (should say "Opens with your current backup passphrase") → Restore → data back.
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

## Custom categories (schema v8, 2026-10-06)
- Designs `06i-categories`, `06j-new-category`. Categories stay neutral (DESIGN.md): name + icon only, no colour picker (`color` column written 0).
- `categories.hidden`: hidden ones keep past payments, are left out of pickers (`watchCategories()`; filters pass `includeHidden: true`), and `CategoryResolver.load` skips rules filing into them.
- `LedgerRepository`: `addCategory` (last in sort order), `updateCategory` (name/icon, built-ins too), `setCategoryHidden`, `watchCategoryUse` (payment counts). Icon set `categoryIcons` in `widgets/common.dart` (30 Material Symbols).
- Settings → Categories (list: yours / built in / hidden; + adds). Every category picker (detail, add payment, review, subscription) ends with "New category" (`newCategoryTile`).

## Unknown senders + review gaps (2026-10-05, no schema change)
Designs: `03f` unknown-sender editor, `03g` which-bank sheet, `03h` new-bank sheet, `03i` AutoPay-due kind, `03j` not-a-transaction sheet, `03k` queue with new-sender card + Undo, `01c` sync-problem banners, `10b` overdrawn balance. Light inks re-tuned (see below).
- **Unknown sender** (`lib/data/ingest/unknown_sender.dart`): an SMS from a sender no rule knows is probed with a throwaway `ParserEngine` (public API only; the parser's OTP/promo/decline prefilters + `guessFields`). Business sender + amount + payment word → `raw_messages` with `bankId = null`, `needsReview`, note `unknown sender`; else dropped as before. Email never (k only fetches known senders).
- Review: unknown items show "A sender k doesn't know", a Bank row (03g: existing banks or "A bank not in k" → 03h name + optional alert-mail sender). Save → `BankRepository.addBank` (id = name code, "HDFC Bank" → `HDFC`, reuses same-name bank) + SMS sender rule on the header core (`senderCore`: "JD-HDFCBK-S" → "HDFCBK") + optional email rule → `assignBank` gives every waiting message from that sender the bank → normal save & learn → reprocess.
- "Not a bank" blocks the sender core (setting `senders.notBank`, JSON list; `BlockedSenders`), its waiting messages → nonTransaction. Settings → Banks shows "Not banks" with "Read again".
- **AutoPay learning**: editor "Message: Payment | AutoPay due". AutoPay hides direction/account/ref/category, marks DUE ON (`MarkField.dueDate`; a DATE mark converts), learns a `mandate` template (verified: amount + due date read back) and logs an upcoming charge.
- **Skip learning + undo**: "Not a transaction" opens 03j; "Skip messages like this" (default off) learns an `ignore` template = first 20 normalized words, digit words free, anchored (`skipPattern`), priority 50, verified to skip its sample; reprocess now also clears items a format marks nonTransaction. Snackbar Undo (`ReviewUndo`) restores the messages, forgets the skip format / unblocks the sender. Learned formats list shows "skips" / "AutoPay alert".
- **Sync banners** (Transactions): SMS off → "Turn on" (system prompt, else app settings); a failing inbox → "Gmail stopped syncing · Sign in" / IMAP "Fix" (app password). `EmailSync.watch` now re-emits on settings writes so errors show at once. `NoticeBanner` got `detail` + `problem` (alert icon, as 06d).
- **Overdrawn**: Accounts → Set balance has In credit / Overdrawn (not for cards or cash); row meta adds "· overdrawn".
- **Light inks**: ink-10 `#6A3A26`, ink-20 `#557018`, ink-200 `#8A6300` — all ≥4.9:1 on paper and every pair ≥ΔE2000 20 (old 10↔200 was 15). `k_colors.dart`, DESIGN.md, k.pen variables; `08` re-exported.
- Tests: `test/data/unknown_sender_test.dart`, `bank_repository_test.dart` (add account, bank codes). `flutter test` 98 pass.
- Messages from unknown senders that arrived before this build were dropped, not stored: Settings → Sync → read past SMS from a date picks them up (dedup makes it safe).

Device checks:
1. An SMS from a bank k lacks (or a wallet) → Review card "New sender". Pick "A bank not in k", name it, Save & learn → payment logged; Settings → Banks lists the bank with its header.
2. "Not a bank" on another → gone; Undo brings it back; Settings → Banks → Not banks → Read again.
3. An AutoPay alert in Review → Message: AutoPay due → Save & learn → shows under Upcoming.
4. Not a transaction with Skip on → snackbar "…and N more like it" → Undo.
5. Turn off SMS permission → banner; Turn on. Let Gmail expire (7 days) → banner → Sign in.
6. Accounts → Set balance → Overdrawn → row shows −₹ and "overdrawn".
7. Light theme: ₹10 / ₹20 / ₹200 chips now tell apart.

### For the parser session
- Banks learned from unknown senders (Settings → Banks, Message formats samples) are candidates for built-in `BankDefinition`s; use the same code as the app's id (`bankCodeFor`, e.g. `HDFC`) so the seeded row lands on the owner's.
- Skip formats the owner teaches are `ignore` templates in `parser_templates`; recurring ones are worth built-in ignore templates.

## Credit cards, EMIs, 5-tab nav (schema v9, 2026-10-05)
Owner has no credit card yet: no real card samples; card bill / payment-received / statement formats stay unbuilt (parser).
- Designs: `12-accounts-tab`, `12b-credit-card`, `13-recurring`, `13b-convert-to-emi`, `13c-add-loan-emi`, `02d-card-bill-payment`, `02e-card-payment-emi`, `06l-settings-grouped`; bottom nav component now 5 tabs; Transactions top bar is + and search only.
- Schema v9: `accounts.credit_limit_minor`, `transactions.emi_id`, table `emis` (`lib/data/db/tables/emi_tables.dart`); seeded category `cat_card_bill` "Card bill".
- **Card bill ≠ spend** (`lib/data/ingest/card_bill.dart`, `TransferLinker.markCardBill`): a non-card debit whose payee/message looks like a bill payment (CRED, credit card, CC payment, BillDesk card…) becomes a transfer to the card: the card's matching credit within ±3 days, else a card side added by k (`origin user`; a late message becomes it) when the card is named by digits or is the only one, else alone. A card credit later joins a lone bill. Backfill `markCardBillsAll` on start. Detail: "Card bill payment" (force) / "Not a card bill" (unlink).
- **Owed**: `AccountView.owedMinor` = limit − available. Set via Accounts → card → ⋮ / Card limit, or Add account.
- **Refunds**: credit on a credit card that isn't a bill payment = `TxnView.isRefund`; `spentMinor` is signed, so refunds lower spent (month panel, day totals, Summary), never "in".
- **EMIs** (`lib/data/emis/`): `EmiSchedule` (pure), `EmiService` (convert a card purchase, add a loan, edit, stop; `refresh` links debits within ±2% and ±7 days of a due instalment on the EMI's account; runs with subscription refresh). Card EMI `spread` (default): purchase not counted, each due instalment counts in its month via `virtualInstalments` (month panel + Summary only, never listed) unless a real linked charge covers that month; unspread: purchase counts once, linked instalments don't. Loan EMIs count as normal debits. Loan reminders share the subscription reminder channel.
- Nav: Transactions · Review · Recurring · Accounts · Summary. Settings regrouped (Reading / Your data / This phone / About) with sub-pages reusing the old sections.
- Tests: `test/data/credit_card_test.dart`; `flutter test` 111 pass. Emulator-checked on a release build: v8→v9 migration, CRED bill as transfer with card side, card screen, Convert to EMI, Recurring, Settings.

### For the parser session
- Credit card "payment received", statement/bill due ("Total due ₹X, min ₹Y, due …") and refund formats, once the owner (or a tester) has a card. Card-on-UPI (RuPay) messages must give the card's last4 so they land on the card.

## Subscription fixes from Amazon Prime card change (2026-10-05)
- A plan with no charge yet (suggested from an AutoPay alert) took any past debit at its merchant within ±10% (old Amazon order → "Prime"). `_matchCharges` now needs such a debit within ±7 days of the expected day.
- Txn detail: "Not a subscription charge" → `SubscriptionService.unlinkCharge` (unlinks; id kept in setting `subscriptions.notCharges` so match/detect skip it; plan's last/next/amount fall back to the newest charge left, else its pending AutoPay alert; a settled alert goes back to pending). Field reads "<name> · stopped" for a stopped plan.
- Upcoming on Transactions shows only alerts due in the next 30 days (`LedgerRepository.upcomingWindow`).
- Review: switching to AutoPay due (or a parser-guessed AutoPay) turns a DATE mark into DUE ON only if it's after the day the message came; otherwise "Mark or pick".
- Not fixed: AutoPay-alert suggestions are always monthly (the alert doesn't say how often).

## NEXT SESSION: commit, then release
State: everything since `ca4de66` is **uncommitted** (critique fixes, copy trim follow-ups, type scale, Summary drill-ins, quick actions sheet, motion pass; ~40 files incl. DESIGN.md + HANDOFF.md). Owner wants polish done, then a **single commit**. `flutter analyze` clean, `flutter test` 126 pass. Release 1.1.1 (run 37359149330) published fine; CI warns setup-java v4 / Node 20 deprecated and ubuntu-latest → Ubuntu 26 on Oct 19.

**Motion pass done (2026-10-06)**, DESIGN.md Motion updated. All in `lib/ui/motion.dart` (`Motion` tokens 150/220/300ms, emphasized easing, `Motion.off`/`Motion.of` for Remove animations):
1. Tabs: `FadeThroughStack` replaces IndexedStack in `home_shell.dart` (all tabs stay mounted).
2. Pages: `KPageTransitionsBuilder` in theme (predictive back + fade-forwards, instant when animations off); manifest `enableOnBackInvokedCallback="true"`.
3. Live arrival: `Arrival` wraps Transactions rows; `_noteArrivals` in `transactions_screen.dart` marks ids new under the same filter (≤3, occurred <2 days ago, never first load). Row opens + fades, surface-2 wash clears at 1.6s.
4. Month panel: `RollingAmount` total, rosette ink `ColorTween`, `SpendRibbon` now a CustomPainter tweening shares (`SpendRibbon.shares`).
5. Review: `SharedAxisSwitcher` on the editor body (next item slides in); queue is `_AnimatedQueue` (SliverAnimatedList diff: cards collapse out, Undo slides back, mounted even when empty).
6. Summary: trend bars `AnimatedContainer`, category bars tween, calendar fades (AnimatedSwitcher + AnimatedSize keyed by month).
Also: `learned_formats_screen.dart` AnimatedOpacity honours Remove animations.
Emulator-checked (release arm64 APK on `Medium_Phone_API_36.1`; it is arm64, x64 APK won't start): live SMS → row opens, total rolled mid-frame, wash cleared; tab switch, Summary month change; no crashes. Not exercised on emulator: Review queue/editor motion (no review items), predictive back gesture (needs real swipe).
**Polish pass done (2026-10-06):** Review editor header puts the reason on its own line (time no longer truncates; Pencil 03b synced); card screen rows follow 12b (`TxnRow(onCard: true)`: date on every row, no account, bill = "Bill payment · Axis ··1234 · 2 Oct · not spent", no swap icon); Accounts balance meta drops "00:00" for date-only messages. Colour-blind ink collisions: owner accepted as is (DESIGN.md Do's). Emulator round (dark): all 5 tabs, review editor, detail, Settings look right.
Next: commit (owner approves first), then release.

## ATM withdrawal + debit cards (2026-10-07)
Owner hit an Axis ATM withdrawal that went to Review, saved it as ATM withdrawal, and cash in hand didn't change. Also the account mark on `XX100640` picked the wrong digits.
- **Cash:** cash in hand counted only `txnType == atm`; Review saved `other`. Now `watchBalances` also counts the ATM withdrawal category (`atmCategoryId` = `cat_cash`, so the owner's already-saved row counts after updating), Review save sets `txnType: atm` when that category is picked, and a learned format gets default `txnType: atm` (later messages of that shape are ATM withdrawals automatically). Test in `review_service_test.dart`.
- **Account mark:** `trimToField` matched non-overlapping 4-digit chunks (`XX100640` → `1006`); now last 4 of the last digit run (`0640`). Test added.
- **Debit cards on an account:** Accounts → tap a savings/current account → "Add a debit card" (last 4) → `LedgerRepository.addDebitCard`: a debit-card account folded into it (shows "Includes card ··2432"); an auto-made card with those digits is merged with its payments. Messages naming the card log on the account. Test in `transfer_linker_test.dart`. (Sheet item only; no Pencil change.)

**Review marking follow-ups (owner asked, same day):**
- Mark sheet: the selection sits in a read-only TextField, so Android's own handles move start/end inside a word. Untouched → trimmed to the field as before; dragged → kept exactly (`exactField`; account/card must be exactly 4 digits). Tapping a mark starts with its range selected.
- New **Card no.** mark (`MarkField.card`, caption CARD, `learnable: false`): on save the card is added to the payment's savings/current account (`_linkCard` → `addDebitCard`). Not part of the learned format until the parser has a group for it.
- **Edit a learned format:** Message formats → Edit → `ReviewEditorScreen(editTemplateId:)` on the sample (title "Edit format", no category / learn switch / Not a transaction; button "Save format") → `ReviewService.relearn`: new template from the new marks, old one soft-deleted, its messages re-pointed (uses kept), nothing logged; if the new marks don't read the sample back, the old format stays.
- Emulator: Card no. mark from the sheet works (the guess had marked 2432 as ACCOUNT, now CARD). adb long-press on a word didn't open the sheet on this emulator (tap on a mark did); check long-press on the phone.
- **Designs not yet synced** (Pencil app was closed): mark sheet (handles + "Drag the handles to mark part of it" + Card no. chip) and 03e Edit button.

### For the parser session: Axis ATM withdrawal (real, masked)
SMS (no word "ATM"; "AXIS BANK L" is the terminal; `BLOCKCARD XX2432` names the debit card):
`INR 10000.00 debited from A/c no. XX000640 on AXIS BANK L 07-10-2026 19:15:17 IST. Avl bal: INR 5363.50. Not you? SMS BLOCKCARD XX2432 to +919951860002 - Axis Bank`
Email (same payment):
`Dear Customer, Thank you for banking with us. We wish to inform you that INR 10000.00 has been debited from your A/c no. XX000640 on 07-10-2026 19:15:17 at ATM-WDL/AXPR/5947. Available balance: INR 5363.50. Please SMS BLOCKCARD 2432 to +919951860002 or call 1860 500 5555, if the transaction has not been initiated by you.`
Expected: debit, amount 1000000, last4 0640, balance 536350, date 07-10-2026 19:15:17; email txnType atm (ATM-WDL). For the SMS, decide whether "debited … on <terminal> … BLOCKCARD" means ATM or card spend (only this sample so far; the email copy merges with it). Six-digit account numbers (`XX100640` style) must give the last 4. Today the guesser marks the BLOCKCARD digits (2432) as the account: in Axis "BLOCKCARD XXnnnn" is the card, not the account.
**API ask:** a `card` named group (debit card last 4) in `ParsedFields` / `Fields`, so templates (built-in and learned) can read it. The app will then link the card to the account on every message and make `MarkField.card` learnable.

## Device test of 1.1.1 + fixes (2026-10-06)
Owner checked on the phone: wrong passphrase, CSV export, in-app update install all work. Overnight backup did not run (last was 18:20 the evening before; phone was at 6% overnight).
- **Backup:** the 03:00 worker needs battery-not-low, so it waited until charging, then skipped because the last backup was <20h old; app-open catch-up only after 36h. Now worker gap 12h (`_minGap`) and app-open catch-up 26h (`refresh`).
- **Gmail hourly sync visibility:** app-open syncs made "last checked" always fresh. `emailBackgroundMain` now stamps `EmailSync.backgroundAtKey`; Settings → Sync "Check email" shows "Hourly · last background check 14:02" (design 06 updated). Owner to watch it after the next release.
- **Read past email** (Settings → Sync, shown when an inbox exists, design 06): `EmailSync.importSince(from)` re-reads every inbox from a picked date, cursor untouched, dedup makes overlap safe.
- **Transaction detail** (design 02 updated): actions sit above "Came from this bank message"; that section has Hide/Show (`device.detail.hideMessages`, remembered for every payment).
- **Review Undo snackbar never went away:** Flutter now keeps snackbars with an action until tapped (`persist` defaults to true when there's an action); Undo snackbar sets `persist: false`, 6s.
Emulator-checked: detail order + Hide/Show, Undo snackbar times out. Not checked: Read past email (no inbox on emulator), backup timing (device).

## Design critique fixes (2026-10-06)
`/impeccable critique` of the main screens scored 28/40 (snapshot `.impeccable/critique/`). Fixed, design first (01, 01d new, 02*, 03a, 05, 05b/05c new, 12b; DESIGN.md components: FAB, Quick Actions Sheet, Upcoming/Unknown Chip, Upcoming Row, Review Card, Drill-in Row):
- Add payment is a bottom-right "Add" FAB on Transactions only (`home_shell.dart`); top bar = search + settings. List ends with 88dp clearance.
- Long-press a Transactions row → `showTxnQuickActions` (in `txn_detail_screen.dart`, reuses the detail's category / not-a-transaction / self-transfer flows via a throwaway `TxnDetailCubit`; `_remove(popAfter: false)`).
- Upcoming AutoPay rows: dashed text-3 chip with a clock (`NoteChipStyle.upcoming`), title/amount text-2. Review card with no amount: dashed "?" (`NoteChipStyle.unknown`). Chips are `ExcludeSemantics` (rows carry the spoken label).
- Pinned bar shows only the ascending span ("3–5 Oct", `daySpan` in `format.dart`); no "Transactions" heading.
- Summary order: In your accounts, Last 6 months, Where it went, Day by day, then "Top payees" / "By spend size" drill-in rows → full screens (`MonthReport.topPayees` = 10). Panel: "₹X in · Net ₹X" (no budget word "left").
- Review: "N to review" count; reasons "k couldn't read this message" / "Amount not found" / "Account not found" / "Paid or received unclear".
- Detail: band range line dropped (hero chip says it); Delete is an alert-colour text button.
- Account names: `long` = "Axis credit card ··5678" (short bank name, no "Bank") for detail/Accounts/card title; `short` = "Axis card ··5678" in row meta.
- Type scale: 63 `fontSize:` overrides → 2 (both inside fixed-size chips); new KText `heroSecondary` (32) and `chartFigure` (12); nothing under 12dp. Emulator-checked.
- Not fixed: colour-blind collisions in light inks (protan ₹20↔₹200 ΔE 1.5, deutan ₹500↔₹2,000 1.9; dark deutan ₹50↔₹100 4.9) — amounts are always also text; owner to decide. Card screen bill row wording differs from 12b. Review editor header truncates the time next to the reason.
- Emulator gotcha: `-no-snapshot-save` boots the last saved snapshot, so installs/data from the previous run vanish (looks like data loss; it isn't). Its storage is near full: use release APKs (26 MB), not debug.

## Settings on Transactions, accounts total, copy trim (2026-10-06)
- Settings gear moved from the Accounts tab to the Transactions top bar (+, search, gear). Owner's choice: Transactions only.
- Total of all accounts (`accountsTotal` in `accounts_screen.dart`: banks + wallets + cash − card owed; no-balance accounts and limit-less cards left out; `signedInr`): header on Accounts tab ("Total", "After ₹X owed on cards"), and "In your accounts ₹X ›" row on Summary under the month panel (pushes Accounts). Tests `test/ui/accounts_total_test.dart`.
- Copy trim, whole app (owner: too wordy): explainer paragraphs cut or removed, meta lines to one line (e.g. Accounts footer gone, Cash "Counted 1 Oct", "estimated since 4 Oct"). Kept: destructive confirms, fix-it steps, privacy/passphrase promises. Keep new copy to one short line.
- Designs synced: 01/01c/08 (gear), 12/10 (total, no footer), 05 (accounts row), plus copy sync across screens and 11–11d backgrounds.

## Card bill false positives in 1.1.0 (2026-10-05)
Owner (no credit card) saw ordinary debits, mostly one payee, turned into card bills / self transfers after updating. Cause: `markCardBill` matched `credit ?card` etc. against the whole text of every source message (bank emails carry card ads/footers), and marked bills even with no card in k.
- Auto-marking now needs a credit card account in k (else stays a payment; "Card bill payment" on detail still forces). Message text is SMS only, with strict phrases (`_billText`: "credit card bill/payment/dues", "payment to credit card", CC payment, CRED); payee rule unchanged (`_billPayee`).
- One-time repair (`TransferLinker._repairCardBills`, setting `repair.cardBills.v1` = count undone) on start: auto-marked bills (debit, category Card bill, not user-edited) that fail the new rule are unlinked without blocking re-linking; category re-resolved. Can't tell owner-forced bills apart; any forced before this build are undone too.

## Safety net: migration tests, smoke test, backup before update (2026-10-05)
Owner can't always test on the phone or set up the emulator, so releases check themselves.
- **Migration tests** (`test/data/migration_test.dart`): every shipped schema (v1–v9, `drift_schemas/drift_schema_vN.json`, rebuilt from git history) upgrades to the current one with an owner's rows (bank, account, payee, payment) intact, schema validated, seeds present. Helpers in `test/generated_migrations/` (generated). After a schema change, dump the new version + regenerate (commands in the test header and CLAUDE.md); the test loop covers it once `current` is bumped.
- **Smoke test** (`tool/smoke_test.sh <apk>`, needs a running emulator + adb): install → cold start (alive after 20 s, no FATAL / `E/flutter` / `k: … failed` in logcat) → HOME, `am kill`, bank SMS via `adb emu sms send` (one line: the console cuts at a newline) → waits for `k: background SMS drained, logged 1` (new count-only log in `smsBackgroundMain`) → restart. Proven to catch the 1.0.0 R8 crash (empty `proguard-rules.pro` → fails with `WorkDatabase_Impl.<init>`).
  - `release.yml`: after signing check, builds an x86_64 release APK (same code + R8, CI key) and runs the script on an API 34 emulator (`reactivecircus/android-emulator-runner`); a failure stops before tag/publish. The published APK stays arm64-only.
  - `ci.yml`: same smoke job on pushes to main (debug-signed release build), after analyze + tests.
- **Backup before update** (designs `11b`–`11d`, `lib/app/updates.dart`): Update with Drive backup on → "Backing up to Drive first…" (skipped if the last backup is <10 min old) → download. Backup fails → alert line with last backup time, Cancel / Update anyway. Backup off → note + inline "Turn on backup" (opens Backup screen). Restoring that backup is how to undo a bad update (Android won't downgrade without uninstall). Emulator-checked: backup-off dialog + Turn on backup; backing-up/failed states need Drive (device).
- Pencil canvas regrouped: one row per category (01 Transactions … 13 Recurring, Components last), grey labels.

## Releases + in-app updates (2026-10-05)
Repo goes public; `design/k.pen` untracked (`*.pen` ignored; stays local, still in old history by owner's choice). Real account digits masked everywhere (parser fixtures `4b4dadf`; app tests, docs and designs: real last-4s replaced with 1111–5555).
- **Versioning:** semver in `pubspec.yaml`; build number (versionCode) counts releases = number of `v*` tags + 1. First release **1.0.0+1** (same build number as the current dev install, which Android accepts as an update). Fixes Baka's problems: build number was always 1 (pubspec `+1`, no `--build-number`), a tag/pubspec mismatch only warned, the gist was edited by hand, and in the other Flutter repo a tag pushed with GITHUB_TOKEN never triggers the tag workflow. Here one workflow does everything.
- `.github/workflows/ci.yml`: push/PR → analyze, app tests, parser tests.
- `.github/workflows/release.yml` (manual, main only): bump (patch/minor/major/none) + notes + required → version/code → analyze + both test suites → signed release APK (`--dart-define=UPDATE_MANIFEST_URL=<raw gist>`) → apksigner cert must equal `vars.SIGNING_CERT_SHA256` → commit pubspec + annotated tag, atomic push → `gh release create` with `k-x.y.z.apk` → PATCH gist `k-update.json` `{version, version_code, apk_url, sha256, size_bytes, notes, min_version_code}` (required release raises min; else previous min kept).
- Signing: `build.gradle.kts` uses `K_KEYSTORE`/`K_KEYSTORE_PASSWORD`/`K_KEY_ALIAS`/`K_KEY_PASSWORD` env in CI, else the debug key. Owner chose to reuse the Mac's `~/.android/debug.keystore` (alias androiddebugkey, password android; SHA-256 A5:F5:A7:DF:2A:45:28:5E:7F:2D:6C:31:91:25:46:87:3C:F9:1E:49:AF:16:55:1F:37:50:D9:FC:28:1A:79:69) so releases install over the current install and Gmail sign-in (debug SHA-1) keeps working.
- App: `lib/data/update/update_service.dart` (fetch manifest with cache-bust, compare version codes, download to cache/updates, SHA-256 check), `lib/platform/update_bridge.dart` + `android/.../update/UpdateChannel.kt` (`k/update`: appVersion, canInstall, openInstallSettings, install via FileProvider `${applicationId}.updates`), `REQUEST_INSTALL_PACKAGES`. `lib/app/updates.dart`: launch check after unlock (once per launch; "Later" skips that version via `device.update.skipped` unless required), dialog (design `11-update-available`), Settings → About (design 06: version, last check, Check for updates). Local builds have no manifest URL → no checks.
- Setup the owner does once: make the repo public, create the gist (file `k-update.json`, content `{}`), add a PAT with gist scope as `GIST_TOKEN`, the four `K_*` secrets and the two vars. Then Release with bump `none` → 1.0.0.
- 1.0.0 crashed on start (R8, see Gotchas); **1.0.1** (build 2) is the first working release. **1.1.0** (build 3, 2026-10-05): v9 credit cards/EMIs + subscription fixes. Device-tested on 1.0.1: SMS logged with app swiped away + notification, app lock, Drive backup now, import of a backup file, Settings → About update check. Still to check: Gmail sign-in/hourly email worker, overnight backup worker, an in-app update install (Play Protect may block it).

## Parser session task: bank catalogue, second guess, wallets (from `transaction_sms_parser`)
Owner wants all three. Source: [`transaction_sms_parser`](https://github.com/MabudAlam/transaction_sms_parser) (pub.dev 0.0.1, MIT, pure Dart, 2 commits, keyword heuristics: `TransactionEngine.getTransactionInfo(msg)` → account/transaction/balance, no confidence score). Not a replacement for our templates: it guesses and never says "unsure", can't learn, SMS only. Use it as data + a fallback, never to auto-log.

0. **Evaluate first.** Add it as a dev dependency, or copy its tables with MIT attribution. Run it over every fixture in `test/fixtures/*.json`, comparing amount, direction, last4, payee and balance against `expected` and against our `guessFields`. Write the hit rates in this file. Decide whether to depend on it or copy the parts you need. Copying is likely better: one maintainer, version 0.0.1.
1. **Bank catalogue.** Add a `BankDefinition` for every bank it knows (SBI, HDFC, ICICI, PNB, Canara, Union, IDFC First, Yes, IndusInd, Federal, AU, RBL…), with real SMS sender header cores and alert-mail domains where known. `templates: const []` is fine to start. Use ids from the app's `bankCodeFor(name)` (`HDFC`, `ICICI`, `IDFC_FIRST`, `STATE_INDIA` → prefer a short code like `SBI` and tell the main session). That way a bank the owner already added from an unknown sender lands on the same row. Register them in `registry.dart`; the app seeds them automatically. Add a fixture per bank only when you have a real (masked) sample.
2. **Second guess.** When no template matches, also run the package's (or the ported) heuristics. Fill only the fields `guessFields` left null; keep "prefer null over a wrong value". Result stays `needsReview`. The app just shows better Review prefills; no app change needed.
3. **Wallets.** Add definitions for PhonePe, Paytm, Amazon Pay, MobiKwik… and a way to mark an institution as a wallet. Proposed API change: `BankDefinition.kind` (`bank` | `wallet`), default `bank`. Tell the main session the final API; the app will map wallet → `AccountType.wallet` and label it "wallet" in the UI.
4. Keep the rules: mask fixtures, never loosen tests, parser stays pure Dart.

Main session side — **done** (designs `03g` updated, `10` "+", `10c-add-account`, `06k-banks`):
- `BankView.accounts` / `inUse` (has an account or a stored message). Shared searchable picker `lib/ui/widgets/bank_picker.dart` (`showBankPicker`, `filterBanks`; search appears past 6 banks): "Your banks" then "Other banks k reads", optional "A bank not in k". Used by Review (unknown sender), Add account, Settings → Add a bank sender.
- Settings → Banks lists only your banks + "All banks k reads" → `BanksScreen` (06k, search, tap → add sender).
- Accounts → "+" → `AddAccountScreen`: bank (catalogue or new name), Savings/Current/Credit card/Wallet, last 4 (not for wallet), nickname, balance now (In credit/Overdrawn; card = available limit). `LedgerRepository.addAccount` (null if bank+last4 exists; revives a soft-deleted one). Messages for that bank + last 4 land on it.
- Parser session did parts 1 + 3 (`6385f23`): `catalogue.dart` with 20 banks (short codes SBI, HDFC, ICICI, PNB, CANARA, UNION, BOI, CENTRAL, INDIAN, IOB, UCO, IDBI, IDFC_FIRST, YES, INDUSIND, FEDERAL, AU, RBL, BANDHAN, SBI_CARD; senders from memory, unverified) + 5 wallets (PHONEPE, PAYTM, AMAZON_PAY, MOBIKWIK, FREECHARGE; no senders on purpose, learned via unknown sender) and `BankDefinition.kind` (`InstitutionKind.bank|wallet`).
- App follow-up done: `beforeOpen` re-runs the idempotent seeder on every open, so catalogue additions reach existing installs with no migration. `addBank` reuses a bank whose name, name code or id matches ("State Bank of India"/"sbi" → `SBI`), so short catalogue codes need no mapping table. Wallets: `isWalletBank` (from `kind`) → `AccountType.wallet` in `_accountFor`, "Wallet ·" + wallet icon in picker / 06k / Settings; Add account presets type Wallet. Tests switched to a made-up sender (`JD-ZZBANK-S`) since HDFC is built in; wallet test added.
- **Still open: part 0 + 2 (package evaluation, second guess).** The parser session's auto mode refused `dart pub get` of `transaction_sms_parser` (untrusted code). Owner to choose: allow it, have the parser session read the source on GitHub (no download/run) and port the useful rules with MIT attribution, or strengthen `guessFields` without it.

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
- Release builds are R8-shrunk (debug never is): 1.0.0 crashed on start (`NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>`) and lost `ic_stat_k` (notifications off). Fixed by `android/app/proguard-rules.pro` + `res/raw/keep.xml`. Test release APKs on the emulator (`Medium_Phone_API_36.1`, `adb emu sms send AXISBK "…"` for SMS) before publishing. Android in India blocks browser-installed APKs asking for SMS: owner turns off Play Protect scanning to install.
- `.impeccable/review/` is gitignored scratch; `.impeccable/questions/*.state.json` may show as modified — harmless.

## Open items
- Balance after a manual set is "set by you", then estimated by later payments.
- Phase 2 shortcuts: section head shows the whole list's date span (not the span in view); upcoming charges have no account last4 (not stored on `upcoming_charges`); credits with no keyword stay Uncategorized; merchant names from VPAs can be ugly ("Zeptonowcashfree") until Phase 3 renames/merges.
- Widget tests render via `tester.runAsync` + drift streams hang on teardown — screenshot harness was deleted; if adding widget tests, close cubits/DB inside runAsync.
- Design review: second-round fixes self-verified, not re-scored by reviewer.
