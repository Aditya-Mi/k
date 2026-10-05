/// Category for a payment from a bank account to a credit card bill.
const cardBillCategoryId = 'cat_card_bill';

/// Payee names of card bill payments: CRED, "… credit card", "CC payment",
/// BillDesk card…
final _billPayee = RegExp(
  r'\bcred\b|cred\.club|cred club|credclub|credit ?card|\bcc ?(bill|payment|pmt)\b|'
  r'card ?(bill|dues)|\bccbp\b|billdesk.*card|card.*billdesk',
  caseSensitive: false,
);

/// Message wording that says the debit paid a card bill. Strict on purpose:
/// bank messages mention cards in boilerplate ("block your credit card",
/// card offers), which must not count.
final _billText = RegExp(
  r'credit ?card (bill|payment|dues|outstanding)|'
  r'payment (to|towards|for) (your )?credit ?card|'
  r'\bcc ?(bill|payment|pmt)\b|card (bill|dues) payment|'
  r'\bcred\b|cred\.club|\bccbp\b',
  caseSensitive: false,
);

/// A debit that pays a credit card bill. Paying the bill moves money, it
/// isn't spending. [smsText] is the SMS wording only: bank emails carry
/// card ads and footers, so they are never read for this.
bool looksLikeCardBill(String? payee, String smsText) =>
    _billPayee.hasMatch(payee ?? '') || _billText.hasMatch(smsText);

final _maskedCard = RegExp(
  r'(?:x{2,}|\*{2,}|\.{2,})\s?(\d{4})\b',
  caseSensitive: false,
);

/// Last-4 digits named after a mask ("XX5678", "**5678") in [text], so a bill
/// payment can find the card it paid. Excludes [own] (the paying account).
Set<String> maskedDigits(String text, {String? own}) => {
  for (final m in _maskedCard.allMatches(text))
    if (m.group(1) != own) m.group(1)!,
};
