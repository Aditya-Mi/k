import '../bank_definition.dart';
import '../enums.dart';

// Banks and wallets k knows by name before any of their formats are written.
// No templates yet: their alerts go to Review, where the owner teaches them.
// Sender cores and mail domains are the commonly seen ones, not yet checked
// against the owner's messages; replace with verified ones as samples arrive.
// Codes are short ids (like AXIS, KOTAK), not the app's bankCodeFor(name).

BankDefinition _bank(
  String code,
  String name, {
  List<String> sms = const [],
  List<String> email = const [],
}) => BankDefinition(
  code: code,
  name: name,
  smsSenders: sms,
  emailSenders: email,
  templates: const [],
);

// Wallets carry no senders yet: their SMS are mostly offers with amounts in
// them, so they're learned from Review rather than read by default.
BankDefinition _wallet(String code, String name) => BankDefinition(
  code: code,
  name: name,
  smsSenders: const [],
  emailSenders: const [],
  templates: const [],
  kind: InstitutionKind.wallet,
);

final catalogueBanks = [
  _bank(
    'SBI',
    'State Bank of India',
    sms: ['SBIINB', 'SBIUPI', 'CBSSBI', 'ATMSBI'],
    email: ['sbi.co.in'],
  ),
  _bank('HDFC', 'HDFC Bank', sms: ['HDFCBK'], email: ['hdfcbank.net']),
  _bank('ICICI', 'ICICI Bank', sms: ['ICICIB'], email: ['icicibank.com']),
  _bank('PNB', 'Punjab National Bank', sms: ['PNBSMS'], email: ['pnb.co.in']),
  _bank('CANARA', 'Canara Bank', sms: ['CANBNK']),
  _bank('UNION', 'Union Bank of India'),
  _bank('BOI', 'Bank of India', sms: ['BOIIND']),
  _bank('CENTRAL', 'Central Bank of India', sms: ['CENTBK']),
  _bank('INDIAN', 'Indian Bank', sms: ['INDBNK']),
  _bank('IOB', 'Indian Overseas Bank'),
  _bank('UCO', 'UCO Bank', sms: ['UCOBNK']),
  _bank('IDBI', 'IDBI Bank', sms: ['IDBIBK']),
  _bank(
    'IDFC_FIRST',
    'IDFC First Bank',
    sms: ['IDFCFB'],
    email: ['idfcfirstbank.com'],
  ),
  _bank('YES', 'Yes Bank', sms: ['YESBNK'], email: ['yesbank.in']),
  _bank('INDUSIND', 'IndusInd Bank', sms: ['INDUSB'], email: ['indusind.com']),
  _bank(
    'FEDERAL',
    'Federal Bank',
    sms: ['FEDBNK'],
    email: ['federalbank.co.in'],
  ),
  _bank('AU', 'AU Small Finance Bank', sms: ['AUBANK'], email: ['aubank.in']),
  _bank('RBL', 'RBL Bank', sms: ['RBLBNK'], email: ['rblbank.com']),
  _bank('BANDHAN', 'Bandhan Bank'),
  _bank('SBI_CARD', 'SBI Card'),
  _wallet('PHONEPE', 'PhonePe'),
  _wallet('PAYTM', 'Paytm'),
  _wallet('AMAZON_PAY', 'Amazon Pay'),
  _wallet('MOBIKWIK', 'MobiKwik'),
  _wallet('FREECHARGE', 'Freecharge'),
];
