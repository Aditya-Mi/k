import '../bank_definition.dart';
import '../enums.dart';
import '../template.dart';

// Synthetic formats modelled on Bank of Baroda / BOBCARD alerts — replace or
// extend with real samples (see test/fixtures/bob.json).
final bobBank = BankDefinition(
  code: 'BOB',
  name: 'Bank of Baroda',
  smsSenders: const ['BOBTXN', 'BOBSMS', 'BOBCRD'],
  emailSenders: const ['bankofbaroda.com', 'bobfinancial.com'],
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
      pattern: rx(
        r'Rs\.?(?<amount>{amt}) Credited to A/c \.*(?<last4>\d{4}) thru UPI/(?<ref>\d+) by '
        r'(?<payee>\S+?)\. Total Bal:? ?Rs\.?(?<balance>{amt})(?:.*?\((?<date>[\d\-]+)\))?',
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
    ParserTemplate(
      id: 'bob_email_upi',
      bankCode: 'BOB',
      channel: Channel.email,
      name: 'UPI debit/credit (email)',
      pattern: rx(
        r'account X+(?<last4>\d{4}) has been (?<direction>debited|credited) with INR '
        r'(?<amount>{amt}) on (?<date>\d{2}-[A-Za-z]{3}-\d{4} [\d:]+) towards '
        r'UPI/(?<ref>\d+)/(?<payee>\S+?)\. Available balance:? INR (?<balance>{amt})',
      ),
      defaults: const {'txnType': 'upi'},
    ),
  ],
);
