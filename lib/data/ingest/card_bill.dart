/// Category for a payment from a bank account to a credit card bill.
const cardBillCategoryId = 'cat_card_bill';

final _cardBill = RegExp(
  r'\bcred\b|cred\.club|cred club|credclub|credit ?card|\bcc ?(bill|payment|pmt)\b|'
  r'card ?(bill|dues)|\bccbp\b|billdesk.*card|card.*billdesk',
  caseSensitive: false,
);

/// A debit that pays a credit card bill: to CRED, "credit card", "CC payment",
/// BillDesk card… Paying the bill moves money, it isn't spending.
bool looksLikeCardBill(String? payee, String text) =>
    _cardBill.hasMatch(payee ?? '') || _cardBill.hasMatch(text);

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
