import '../bank_definition.dart';
import '../enums.dart';
import '../template.dart';

// Synthetic formats modelled on Kotak alerts — replace/extend with real
// samples (see test/fixtures/kotak.json).
final kotakBank = BankDefinition(
  code: 'KOTAK',
  name: 'Kotak Mahindra Bank',
  smsSenders: const ['KOTAKB'],
  emailSenders: const ['kotak.com'],
  templates: [
    ParserTemplate(
      id: 'kotak_sms_upi_sent',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      name: 'UPI sent',
      pattern: rx(
        r'Sent Rs\.?(?<amount>{amt}) from Kotak Bank AC X(?<last4>\d{4}) to (?<payee>\S+) '
        r'on (?<date>[\d\-]+)\.? ?UPI Ref:? ?(?<ref>\d+)',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'kotak_sms_upi_received',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      name: 'UPI received',
      pattern: rx(
        r'Received Rs\.?(?<amount>{amt}) in your Kotak Bank AC X(?<last4>\d{4}) from '
        r'(?<payee>\S+) on (?<date>[\d\-]+)\.? ?UPI Ref:? ?(?<ref>\d+)',
      ),
      defaults: const {'direction': 'credit', 'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'kotak_sms_card_spend',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      name: 'Credit card spend',
      pattern: rx(
        r'INR (?<amount>{amt}) spent on Kotak Credit Card x(?<last4>\d{4}) on '
        r'(?<date>\d{2}-[A-Za-z]{3}-\d{4}) at (?<payee>.+?)\. Avl Lmt:? INR (?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'card'},
    ),
    ParserTemplate(
      id: 'kotak_sms_transfer_debit',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      name: 'IMPS/NEFT/RTGS debit',
      pattern: rx(
        r'Kotak Bank A/c X(?<last4>\d{4}) debited by Rs\.?(?<amount>{amt}) on '
        r'(?<date>[\d\-]+) via (?<type>IMPS|NEFT|RTGS) to (?<payee>.+?)\. '
        r'(?:IMPS|NEFT|RTGS) Ref No:? ?(?<ref>\w+)\. Avl Bal:? Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit'},
    ),
    ParserTemplate(
      id: 'kotak_sms_transfer_credit',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      name: 'NEFT/IMPS/RTGS credit',
      pattern: rx(
        r'A/c X(?<last4>\d{4}) is credited by Rs\.?(?<amount>{amt}) on (?<date>[\d\-]+) '
        r'via (?<type>NEFT|IMPS|RTGS) from (?<payee>.+?), Ref:? (?<ref>\w+)\. '
        r'Avl Bal:? Rs\.?(?<balance>{amt})',
      ),
      defaults: const {'direction': 'credit'},
    ),
    ParserTemplate(
      id: 'kotak_sms_upi_mandate',
      bankCode: 'KOTAK',
      channel: Channel.sms,
      kind: TemplateKind.mandate,
      name: 'UPI AutoPay upcoming debit',
      pattern: rx(
        r'Rs\.?(?<amount>{amt}) will be debited from your Kotak Bank AC X(?<last4>\d{4}) '
        r'on (?<dueDate>[\d\-]+) towards (?<payee>.+?) for UPI-Mandate\. UMN:? (?<mandateRef>\w+)',
      ),
    ),
    ParserTemplate(
      id: 'kotak_email_upi',
      bankCode: 'KOTAK',
      channel: Channel.email,
      name: 'UPI debit/credit (email)',
      pattern: rx(
        r'your account xx(?<last4>\d{4}) is (?<direction>debited|credited) (?:for|with) '
        r'Rs\.? ?(?<amount>{amt}) on (?<date>[\d\-]+) towards UPI transaction (?:to|from) '
        r'(?<payee>\S+?)\.? UPI reference number:? (?<ref>\d+)',
      ),
      defaults: const {'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'kotak_email_card_spend',
      bankCode: 'KOTAK',
      channel: Channel.email,
      name: 'Credit card spend (email)',
      pattern: rx(
        r'A transaction of INR (?<amount>{amt}) has been made on your Kotak Credit Card '
        r'xx(?<last4>\d{4}) at (?<payee>.+?) on (?<date>\d{2}-[A-Za-z]{3}-\d{4} at [\d:]+)',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'card'},
    ),
  ],
);
