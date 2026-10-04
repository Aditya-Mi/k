# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users
One person: the developer-owner, an Indian salaried professional with accounts at Axis, Kotak and Bank of Baroda (savings + credit cards), paying mostly by UPI. Uses the app in two moments, equally often: a few-second glance right after paying ("did it log, what's this month at"), and a sit-down weekly/monthly review (go through spends, fix review items, check subscriptions).

## Product Purpose
Automatically logs every payment by reading bank transaction SMS and bank alert emails, so nothing has to be typed in. Main job: **know where money goes** — categories, merchants, trends, recurring charges. No budgets or spending limits (not requested). Success = the ledger is complete and trustworthy without manual entry, and a glance answers "where did my money go".

## Positioning
Fully on-device and private: messages are parsed locally, the database is encrypted, nothing is sent to any server. Built for one person's real banks and message formats, with a correction flow that teaches the parser new formats.

## Operating Context
- Data arrives silently in the background from SMS (instant) and Gmail (hourly) — the user mostly *reviews* rather than *enters*.
- Unparsed bank messages land in a "Needs review" queue; the user fixes fields by selecting text in the raw message, which can become a new parser template.
- The same payment often arrives twice (SMS + email) and is merged.
- Subscriptions are detected from repeat charges and UPI AutoPay / e-mandate "will be debited" alerts; user confirms or dismisses suggestions and gets reminders before renewals.
- Device: Nothing Phone 2 (6.7"), used one-handed, phone mostly in dark mode.

## Capabilities and Constraints
- Screens: transactions list (filter by date, account, category, debit/credit; search), transaction detail (with raw message), needs-review queue, subscriptions (active, next charge, monthly/yearly totals, price-change flag, "unused" toggle), monthly summary (spend by category), settings (bank senders, Gmail accounts, sync, backup/export), app lock (biometric/device credential).
- INR only for now; money stored in paise; other currencies later.
- Accounts auto-created from last 4 digits; user can rename/merge.
- Sideloaded personal APK; never on Play Store. Flutter, Material 3 base widgets.
- Later (not now): self-account transfer linking, multi-device encrypted sync, other currencies.

## Brand Commitments
App name is "k" (lowercase). No other brand assets exist.

## Evidence on Hand
No real transaction data yet in the app; bank message formats are being collected. Designs must use realistic but fictional Indian merchants/amounts (Swiggy, Zepto, Netflix, IRCTC, UPI payees) — never invent features beyond the list above.

## Product Principles
1. Zero typing: the app captures; the user only confirms or corrects.
2. Trust is visible: every transaction traces back to its raw SMS/email.
3. Glance first, depth on demand: the month's picture in one look, detail one tap away.
4. Private by construction: nothing leaves the phone.
5. Teach, don't repeat: one correction fixes all future messages of that shape.

## Accessibility & Inclusion
One-handed use on a 6.7" phone: primary actions within thumb reach (bottom). Dark mode is the primary theme and must be first-class; light mode still supported.
