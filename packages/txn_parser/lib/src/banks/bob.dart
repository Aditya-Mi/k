import '../bank_definition.dart';
import '../enums.dart';
import '../template.dart';

// SMS UPI debit (Dr/Cr) and UPI credit are verified against real samples; other formats are
// still synthetic (see test/fixtures/bob.json). BOB sends no email alerts.
final bobBank = BankDefinition(
  code: 'BOB',
  name: 'Bank of Baroda',
  // BOBSMS seen on real alerts; BOBTXN/BOBCRD unverified.
  smsSenders: const ['BOBSMS', 'BOBTXN', 'BOBCRD'],
  emailSenders: const [],
  templates: [
    ParserTemplate(
      id: 'bob_sms_upi_debit',
      bankCode: 'BOB',
      channel: Channel.sms,
      name: 'UPI debit (Dr/Cr)',
      pattern: rx(
        r'Rs\.?(?<amount>{amt}) Dr\. from A/C X+(?<last4>\d{4}) and Cr\. to (?<payee>\S+?)\. '
        r'Ref:? ?(?<ref>\d+)\. AvlBal:? ?Rs\.?(?<balance>{amt})\((?<date>[\d:]+ [\d:]+)\)',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'bob_sms_upi_credit',
      bankCode: 'BOB',
      channel: Channel.sms,
      name: 'UPI credit',
      // No account number or payer in this format.
      pattern: rx(
        r'Your account is credited with {rs}(?<amount>{amt}) on '
        r'(?<date>\d{4}-\d{2}-\d{2} [\d:]+(?: [AP]M)?) by UPI Ref No:? (?<ref>\d+);? '
        r'AvlBal:? ?Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'credit', 'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'bob_sms_card_spend',
      bankCode: 'BOB',
      channel: Channel.sms,
      name: 'BOBCARD spend',
      pattern: rx(
        r'Rs\.?(?<amount>{amt}) was spent on your card XX(?<last4>\d{4}) at (?<payee>.+?) '
        r'on (?<date>[\d\-]+ [\d:]+)\. Available limit:? Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'card'},
    ),
    ParserTemplate(
      id: 'bob_sms_transfer_credit',
      bankCode: 'BOB',
      channel: Channel.sms,
      name: 'NEFT/IMPS/RTGS credit',
      pattern: rx(
        r'A/c X+(?<last4>\d{4}) credited with Rs\.?(?<amount>{amt}) on (?<date>[\d\-]+) by '
        r'(?<type>NEFT|IMPS|RTGS)-(?<ref>\w+)-(?<payee>.+?)\. Avl Bal:? Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'credit'},
    ),
    ParserTemplate(
      id: 'bob_sms_atm',
      bankCode: 'BOB',
      channel: Channel.sms,
      name: 'ATM withdrawal',
      pattern: rx(
        r'Rs\.?(?<amount>{amt}) withdrawn at ATM \S+ from A/c X+(?<last4>\d{4}) on '
        r'(?<date>[\d\-]+ [\d:]+)\. AvlBal:? ?Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'atm'},
    ),
    ParserTemplate(
      id: 'bob_sms_mandate',
      bankCode: 'BOB',
      channel: Channel.sms,
      kind: TemplateKind.mandate,
      name: 'Mandate upcoming debit',
      pattern: rx(
        r'A/c X+(?<last4>\d{4}) will be debited Rs\.?(?<amount>{amt}) on '
        r'(?<dueDate>[\d\-]+) for (?<payee>.+?) mandate UMRN:? (?<mandateRef>\w+)',
      ),
    ),
  ],
);
