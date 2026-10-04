---
name: k
description: A private, on-device payment ledger where every amount carries the ink of the banknote you would have paid it with.
colors:
  bg: "#101114"
  surface-1: "#17181C"
  surface-2: "#1F2126"
  surface-3: "#2A2C33"
  outline: "#34363E"
  text: "#ECEAE4"
  text-2: "#A9A79F"
  text-3: "#8C8A82"
  on-ink: "#101114"
  alert: "#FF8A65"
  alert-bg: "#3A2019"
  ink-10: "#B07A52"
  ink-20: "#B9C46A"
  ink-50: "#4CC3D9"
  ink-100: "#A79BE0"
  ink-200: "#F2B705"
  ink-500: "#A8A59B"
  ink-2000: "#E0609A"
  bg-light: "#F6F4EE"
  surface-1-light: "#FFFFFF"
  surface-2-light: "#EEEBE3"
  surface-3-light: "#E3DFD5"
  outline-light: "#D3CEC2"
  text-light: "#17181C"
  text-2-light: "#55534C"
  text-3-light: "#69665D"
  on-ink-light: "#FFFFFF"
  alert-light: "#B23A1B"
  alert-bg-light: "#FBE3DA"
  ink-10-light: "#7A4A2A"
  ink-20-light: "#626E14"
  ink-50-light: "#0F7486"
  ink-100-light: "#5845B0"
  ink-200-light: "#835F00"
  ink-500-light: "#66635A"
  ink-2000-light: "#A51E5E"
typography:
  amount-hero:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "40dp"
    fontWeight: 700
    fontFeature: "tnum"
    fontVariation: "'wdth' 112"
  headline:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "22dp"
    fontWeight: 600
    fontVariation: "'wdth' 112"
  title:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "16dp"
    fontWeight: 600
    fontVariation: "'wdth' 112"
  amount-row:
    fontFamily: "Archivo, Roboto, sans-serif"
    fontSize: "16dp"
    fontWeight: 600
    fontFeature: "tnum"
    fontVariation: "'wdth' 112"
  body:
    fontFamily: "Roboto, sans-serif"
    fontSize: "15dp"
    fontWeight: 400
  meta:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12.5dp"
    fontWeight: 400
    fontFeature: "tnum"
  day-header:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12.5dp"
    fontWeight: 500
  label:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12dp"
    fontWeight: 500
rounded:
  chip: "2dp"
  chip-lg: "4dp"
  control: "8dp"
  card: "12dp"
  indicator: "16dp"
  full: "9999dp"
spacing:
  gutter: "16dp"
  row-gap: "14dp"
  row-pad-y: "10dp"
  section-sm: "16dp"
  section-lg: "24dp"
components:
  note-chip-debit:
    backgroundColor: "{colors.ink-200}"
    rounded: "{rounded.chip}"
    width: "24dp"
    height: "12dp"
  note-chip-credit:
    backgroundColor: "transparent"
    rounded: "{rounded.chip}"
    width: "24dp"
    height: "12dp"
  note-chip-large:
    backgroundColor: "{colors.ink-500}"
    textColor: "{colors.on-ink}"
    typography: "{typography.title}"
    rounded: "{rounded.chip-lg}"
    width: "60dp"
    height: "28dp"
  txn-row:
    textColor: "{colors.text}"
    typography: "{typography.body}"
    padding: "10dp 16dp"
  month-note-panel:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.text}"
    rounded: "{rounded.card}"
    padding: "16dp"
  filter-chip:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "32dp"
  button-primary:
    backgroundColor: "{colors.text}"
    textColor: "{colors.on-ink}"
    typography: "{typography.title}"
    rounded: "{rounded.full}"
    height: "52dp"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    typography: "{typography.title}"
    rounded: "{rounded.full}"
    height: "40dp"
  raw-message-card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.text-2}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
    padding: "16dp"
  nav-bar:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.text-2}"
    typography: "{typography.label}"
  nav-indicator:
    backgroundColor: "{colors.surface-3}"
    rounded: "{rounded.indicator}"
    width: "64dp"
    height: "32dp"
  alert-badge:
    backgroundColor: "{colors.alert-bg}"
    textColor: "{colors.alert}"
    typography: "{typography.meta}"
    rounded: "{rounded.control}"
---

# Design System: k

## Overview

**Creative North Star: "The Note Ink Ledger"**

k reads like a ledger kept in banknote ink. Every amount carries the colour of the RBI note you would have paid it with, so the size of a spend registers as colour before the number is read. Everything else steps back: a near-black ground with flat tonal steps, paper-white type, neutral Material Symbols, and Material 3 controls left plain. The inks are the only saturated thing on screen, and they mean one thing.

The density is a working list, not a dashboard. A screen is one column at a 16dp gutter: the month on a note-shaped panel, a row of filter chips, and day-grouped rows of chip, payee and amount. Depth is tonal, never cast. The one ornament is the guilloche rosette on the month panel, drawn in hairlines in the month total's ink, borrowed from the security printing of the notes themselves.

Dark is the primary theme; light is the same system with the inks deepened for a paper ground. Category-coloured donuts and tonal category cards are the confirmed rejection: categories are neutral, amounts are inked.

**Key Characteristics:**
- Seven denomination inks, used only to encode amount band.
- Debit is a filled note chip, credit is an outlined chip with +₹, pending is the filled chip at 45%.
- Archivo, semi-expanded with tabular figures, for amounts and heads; Roboto for everything that is read.
- Flat colour and tonal surface steps; no shadows, gradients or glass.
- Every transaction traces to its raw bank message, shown verbatim.

## Colors

A neutral near-black (or warm paper) ground with seven banknote inks that carry amount band and nothing else.

### Primary
The system has no brand accent. The primary action colour is the text colour itself: **Paper White** (text) filled buttons and switch tracks with an **Ink Black** (on-ink) label. Emphasis comes from inversion, not hue.

### Secondary: the Denomination Inks
- **Ten Brown** (ink-10): spends under ₹20.
- **Twenty Lime** (ink-20): ₹20–49.
- **Fifty Fluoro Blue** (ink-50): ₹50–99.
- **Hundred Lavender** (ink-100): ₹100–199.
- **Two Hundred Yellow** (ink-200): ₹200–499.
- **Five Hundred Stone** (ink-500): ₹500–1,999.
- **Two Thousand Magenta** (ink-2000): ₹2,000 and up.

Each ink has a deepened light-theme twin (`-light` keys) that holds at least 4.9:1 on the paper ground.

### Tertiary
- **Coral Alert** (alert on alert-bg): a changed fact, such as a subscription price rise. Rare by design.

### Neutral
- **Ink Black** (bg): the page ground; also the label colour on primary fills.
- **Surface 1 / 2 / 3** (surface-1, surface-2, surface-3): tonal steps. Surface 1 carries the navigation bar and message cards, surface 2 the month note panel, surface 3 the nav indicator, selected segments and message marks.
- **Hairline** (outline): dividers between detail fields, chip and card outlines.
- **Paper White** (text): payees, amounts, titles.
- **Worn Grey** (text-2): meta lines, day headers, unselected nav labels, raw message body.
- **Faded Grey** (text-3): placeholders, hints and the lowest-priority meta.

### Named Rules
**The One Job Rule.** A denomination ink appears only where it encodes the band of a specific amount: note chips, the denomination ribbon, band bars, the guilloche of the month total, and the amount mark in a message being reviewed. Never for categories, accounts, status, focus, selection or decoration.

**The Fill Means Out Rule.** Debit is a filled chip; credit is the same chip outlined in its band ink with a +₹ amount; pending, upcoming and unparsed amounts are the filled chip at 45% opacity. Direction is never carried by red and green.

**The Calm Count Rule.** Review counts, badges and the review banner are neutral. Coral alert is reserved for a changed fact (a price rise), never for a queue waiting on the user.

## Typography

**Display Font:** Archivo (with Roboto fallback), semi-expanded (wdth 112), weights 600 and 700
**Body Font:** Roboto

**Character:** Archivo's wide, firm figures do the work of a printed denomination; Roboto stays the quiet Android voice for everything read rather than counted.

### Hierarchy
- **Amount Hero** (Archivo 700, 40dp, tabular): the month total on the note panel and the amount on transaction detail.
- **Headline** (Archivo 600, 22dp): screen titles (Subscriptions, Review, Settings, the summary month).
- **Title** (Archivo 600, 16dp): section heads ("Transactions", "Next charges", "Where it went") and the numeral on the large note chip.
- **Amount Row** (Archivo 600, 16dp, tabular): right-aligned amounts in every list row.
- **Body** (Roboto 400, 15dp): payee names, field values, raw message text.
- **Meta** (Roboto 400, 12.5dp, text-2): category · account · time lines under payees.
- **Day Header** (Roboto 500, 12.5dp, text-2): day group labels with their right-aligned "₹702 out" totals.
- **Label** (Roboto 500, 12dp): navigation labels; the selected destination steps up to text colour and a heavier weight.

### Named Rules
**The Counted Figure Rule.** Every amount set as a figure (row, hero, column total) is Archivo at wdth 112 with tabular figures, so columns of amounts align digit for digit. The Pencil renders could not carry the width axis or tnum; the Flutter build must.

**The Indian Grouping Rule.** Amounts use Indian digit grouping and the ₹ sign: ₹1,12,000, never ₹112,000 or INR. Paise show only where the source message carries them (detail and review).

## Layout

A single column on a 412dp-wide phone with a 16dp gutter. Sections are separated by 16–24dp. List rows use 10dp vertical padding and a 14dp gap between chip, text block and amount; the amount column is right-aligned at the gutter. Lists group by day with a day header carrying the day's total out; the list section head shows the date span currently in view and sticks while scrolling. Primary actions sit at the bottom of the screen in thumb reach, full-width or as a pair (outlined secondary left, filled primary right). Bottom navigation has four destinations: Transactions, Review, Subscriptions, Summary. Detail screens use label-left, value-right field rows separated by hairlines.

## Elevation & Depth

Flat. There are no shadows anywhere; depth is a step up the neutral surface scale (bg → surface-1 → surface-2 → surface-3) or a hairline outline. Light theme follows the same steps on paper.

### Named Rules
**The Flat Ink Rule.** Colour is committed and flat: no gradients, no glass, no blur, no cast shadows. If something needs to stand forward, it moves one surface step, or gets a hairline.

## Shapes

Small, banknote-proportioned rectangles for anything inked; soft 12dp cards for containers; full pills for buttons. The note chip (24×12dp, 2dp corners) and its large form (60×28dp, 4dp corners, carrying the band's lower bound, e.g. "500+") are always 2:1 rectangles. Filter chips are 32dp high with 8dp corners. The nav indicator is a 64×32dp lozenge with 16dp corners. Bars (denomination ribbon, band bars, subscription cycle bars, category bars) have fully rounded ends.

### Named Rules
**The Note Proportion Rule.** An amount's ink is always shown as a note-shaped rectangle or a bar, never as a dot, circle or avatar.

## Components

### Buttons
- **Shape:** fully rounded pill (9999dp), 40–52dp high.
- **Primary:** filled in text colour with a bg-coloured label and optional leading icon ("Save & learn", "Track it", "Unlock"). At most one per screen.
- **Secondary:** outlined pill, hairline outline, text-coloured label ("Not a transaction", "Delete").
- **Text:** plain text-coloured label with no container, for the dismissive half of a suggestion ("Not a subscription").
- **States:** pressed and focus states follow Material 3 defaults over these colours; not yet specified beyond that.

### Chips
- **Note Chip:** 24×12dp, 2dp corners. Filled in band ink for debit, 1.5dp outline in band ink for credit, filled at 45% for pending, upcoming and unparsed.
- **Large Note Chip:** 60×28dp, 4dp corners, carrying the band's lower bound, e.g. "500+" ("500") in on-ink; leads the hero amount on detail.
- **Filter Chip:** 32dp high, 8dp corners, hairline outline, text label with a trailing dropdown arrow; scrolls horizontally off the gutter.
- **Status tags:** "Marked unused" is an outlined 8dp tag in text-3, and the whole row dims; "Price up" is an alert-badge (alert text on alert-bg) with an up arrow.

### Cards / Containers
- **Corner Style:** 12dp.
- **Background:** surface-2 for the month note panel; surface-1 or transparent with a hairline for message cards, suggestion cards and the review banner.
- **Shadow Strategy:** none; see Elevation & Depth.
- **Border:** 1dp outline on outlined cards.
- **Internal Padding:** 16dp.

### Inputs / Fields
- **Field rows:** label in text-2 left, value in text right, 1dp hairline between rows. Editable values open in place; placeholders ("Add a note") sit in text-3.
- **Segmented button:** Material 3 segmented control, pill, selected segment on surface-3 with a check.
- **Dropdown:** outlined 8dp field ("Choose") with a trailing arrow.
- **Switch:** track in text colour, thumb in bg with a check when on.

### Navigation
- **Bottom Nav:** Material 3 navigation bar on surface-1, four destinations with Material Symbols Rounded icons over 12dp labels. Selected destination: surface-3 indicator (64×32dp) behind the icon, label in text colour. Unselected: icon and label in text-2. The Review badge is neutral: a small text-coloured disc with a bg-coloured count.
- **Top App Bar:** home shows the lowercase "k" wordmark in Archivo with search and settings actions; inner screens show a back or close icon, an Archivo 22dp title, and actions on the right.

### Txn Row
Note chip · payee (Body) over meta (Meta) · amount (Amount Row) right-aligned. An optional merged icon sits before the amount when the row came from more than one message. Row states (pending, unused, merged) restyle the chip and text tone without moving the columns.

### Month Note Panel
The signature. A surface-2 card at about 2.07:1 holding the month and sync state, the Amount Hero total, an in/out line, and a full-width denomination ribbon: one rounded bar split into band segments in their inks, proportional to how the month's spend divides across note bands, captioned with spend count and the dominant band's share. Anchored in the card's right third, whole and clear of the ribbon, is a guilloche rosette (hypotrochoid bands and rings, 0.5dp hairlines) in the ink of the month total's band. On the lock screen the same card hides the total and draws the rosette in neutral grey.

**The Guilloche Rule.** The rosette appears only on the month note panel (and its locked twin), always as hairlines, always in the month total's ink or neutral. It is never a background texture, never filled, never on another card.

### Subscription Cycle Bar
Under each subscription row: a rounded bar whose track length is the billing cycle (a yearly plan draws a full-width track, a monthly plan a short one) and whose fill is the time left before the next charge.

### Raw Message Card
The verbatim SMS or email, on an outlined 12dp card: sender and channel icon, channel · timestamp in meta, then the message text in text-2 Roboto. When two messages were merged into one transaction, the secondary card carries a **MERGED** stamp: outlined, slightly rotated, letterspaced capitals in text-2, like a rubber stamp on a ticket.

**The Struck Not Gone Rule.** Merged and deleted records stay visible, marked with a stamp, so the trail back to every bank message is never broken.

### Message Marks (review)
In the review editor the raw message is tokenised: each recognised field value sits on a surface-3 mark with a 2dp underline, and a small letterspaced capital caption (ACCOUNT, DIRECTION, AMOUNT, PAYEE, REF, DATE) floats above it in text-3. The amount mark alone takes the band ink on its caption and underline. These captions name parsed fields; they are not a general label style.

### System Biometric Prompt
App lock defers to Android's BiometricPrompt, which the app does not draw. The app owns only the lock screen behind it: the locked note panel, "k is locked", and a bottom primary Unlock button.

### Motion
Not yet specified. To be authored in the Flutter build and recorded here then.

## Do's and Don'ts

### Do:
- **Do** colour an amount's chip by its band: ink-10 under ₹20 through ink-2000 at ₹2,000 and up, using the `-light` twins on the paper theme.
- **Do** set every figure amount in Archivo at wdth 112 with tabular figures, right-aligned, with Indian grouping (₹1,12,000).
- **Do** show categories with neutral Material Symbols Rounded in text-2, and category bars and subscription cycle fills in the text colour. Never text-2 for a bar: it is near-identical to ink-500 (1.02:1) and would read as the ₹500 band.
- **Do** make depth with surface steps (bg, surface-1, surface-2, surface-3) and 1dp hairlines.
- **Do** make the one primary action a text-coloured pill with a bg-coloured label, at the bottom in thumb reach.
- **Do** keep the raw bank message one tap from any transaction, verbatim.

### Don't:
- **Don't** use a denomination ink for a category, account, status, selection, focus ring or decoration.
- **Don't** mention notes, denominations or cash in user-facing copy. Most payments are UPI; the inks are a size scale borrowed from banknote colours, not a claim about how the user paid. Name bands as spend ranges ("Under ₹20", "₹500–1,999", "₹2,000+") and the breakdown "By spend size". Note/denomination wording stays internal (token and component names, this rationale).
- **Don't** show debit and credit as red and green; use filled versus outlined chips and +₹.
- **Don't** colour the review count, badge or banner with alert; coral is only for a changed fact like a price rise.
- **Don't** use gradients, glass, blur or drop shadows.
- **Don't** draw the guilloche anywhere but the month note panel and its locked twin.
- **Don't** reuse the review editor's letterspaced capital field captions as section labels or eyebrows elsewhere.
- **Don't** draw a custom biometric dialog; use the system BiometricPrompt.
