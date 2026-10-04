---
version: 1
slug: "design-k-pen"
primary_target: "design/k.pen"
related_targets: []
---

# Surface: k app shell (all MVP screens), design in design/k.pen

Mode: Operate. Android phone (Nothing Phone 2, 412×915dp), dark-first, one-handed.
Screens: transactions (home), transaction detail, needs-review queue + review editor, subscriptions, monthly summary, settings, app lock; one light-mode check of the home screen.
Job: glance after paying ("did it log, where is the month at") and weekly review (fix review items, check subscriptions, see where money goes). No budgets.
Constraints: Material 3 navigation and controls (bottom navigation bar, top app bars, chips, switches, bottom sheets, snackbars); 48dp targets; primary actions in thumb reach; INR with Indian digit grouping (₹1,12,000).

## Direction contract
THESIS: Every amount carries the ink of the RBI banknote you would have paid it with, so a spend's size reads as colour before you read the number. Refuses the category default of category-coloured donuts and tonal cards.
OWN-WORLD: Near-black ground #101114 with tonal steps; paper-white text #ECEAE4. Seven denomination inks used only to encode amount band: ₹10 brown #B07A52 (<₹20), ₹20 green-yellow #B9C46A (₹20–49), ₹50 fluoro blue #4CC3D9 (₹50–99), ₹100 lavender #A79BE0 (₹100–199), ₹200 yellow #F2B705 (₹200–499), ₹500 stone #A8A59B (₹500–1,999), ₹2000 magenta #E0609A (≥₹2,000). Debit = filled note chip; credit = outlined chip and +₹. Amount/heading face Archivo (semi-expanded, tabular figures), body Roboto. Categories carry Material Symbols in neutral tone, never ink.
STORY: Open, see the month on a note-shaped panel and today's spends as a column of inked chips; spot the red-free, flat review count; tap any row to see the exact SMS/email it came from; fix or teach; leave.
FIRST VIEWPORT: Top app bar (k, search, settings). Month note panel (aspect ~2.2:1, faint guilloche linework in the month total's ink): month, total out, total in, and a denomination ribbon showing how the month's spend splits across note bands. Filter chips row. Review banner chip if items wait. Day-grouped list: note chip · payee + category/account line · amount. Sticky header shows the date span in view. Bottom navigation: Transactions, Review (badge), Subscriptions, Summary.
FORM: Note Inks, my rank 1 (Impeccable's pick, chosen over the rolled Station Board); seed key 6a76d567. Raises kept: sticky date-span header (lexicon); row states restyle without breaking columns (split-flap); subscription bars length=cycle, fill=time left (labanotation); flat committed colour, no gradients/glass (guide map); merged/deleted rows stay struck with a stamp (ticket wallet); inks do one job only (monochrome).
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Unresolved: real bank formats pending; light theme derived from the same inks deepened for paper ground.
