import '../bank_definition.dart';
import '../enums.dart';
import '../template.dart';

// Synthetic formats modelled on Axis alerts — replace/extend with real
// samples (see test/fixtures/axis.json).
final axisBank = BankDefinition(
  code: 'AXIS',
  name: 'Axis Bank',
  smsSenders: const ['AXISBK'],
  emailSenders: const ['axisbank.com'],
  templates: [
    ParserTemplate(
      id: 'axis_sms_upi',
      bankCode: 'AXIS',
      channel: Channel.sms,
      name: 'UPI debit/credit',
      pattern: rx(
        r'INR (?<amount>{amt}) (?<direction>debited|credited) A/c no\. XX(?<last4>\d{4}) '
        r'(?<date>[\d\-]+,? [\d:]+)(?: IST)? UPI/P2[AM]/(?<ref>\d+)/(?<payee>.+?) Not you',
      ),
      defaults: const {'txnType': 'upi'},
    ),
    ParserTemplate(
      id: 'axis_sms_card_spend',
      bankCode: 'AXIS',
      channel: Channel.sms,
      name: 'Credit card spend',
      pattern: rx(
        r'Spent INR (?<amount>{amt}) Axis Bank Card no\. XX(?<last4>\d{4}) '
        r'(?<date>[\d\-]+ [\d:]+)(?: IST)? (?<payee>.+?) Avl Limit:? INR (?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'card'},
    ),
    ParserTemplate(
      id: 'axis_sms_bank_transfer_credit',
      bankCode: 'AXIS',
      channel: Channel.sms,
      name: 'NEFT/IMPS/RTGS credit',
      pattern: rx(
        r'INR (?<amount>{amt}) credited to A/c no\. XX(?<last4>\d{4}) on '
        r'(?<date>[\d\-]+ at [\d:]+)(?: IST)?\. Info- (?<type>NEFT|IMPS|RTGS)/(?<ref>\w+)/'
        r'(?<payee>.+?)\. Avl Bal- INR (?<balance>{amt})',
      ),
      defaults: const {'direction': 'credit'},
    ),
    ParserTemplate(
      id: 'axis_sms_atm',
      bankCode: 'AXIS',
      channel: Channel.sms,
      name: 'ATM withdrawal',
      pattern: rx(
        r'INR (?<amount>{amt}) withdrawn at ATM \S+ from A/c no\. XX(?<last4>\d{4}) on '
        r'(?<date>[\d\-]+ [\d:]+)\. Avl Bal INR (?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'atm'},
    ),
    ParserTemplate(
      id: 'axis_sms_mandate',
      bankCode: 'AXIS',
      channel: Channel.sms,
      kind: TemplateKind.mandate,
      name: 'e-mandate upcoming debit',
      pattern: rx(
        r'e-mandate for (?<payee>.+?) of INR (?<amount>{amt}) will be debited from '
        r'A/c no\. XX(?<last4>\d{4}) on (?<dueDate>[\d\-]+)\. UMRN:? (?<mandateRef>\w+)',
      ),
    ),
    ParserTemplate(
      id: 'axis_email_card_spend',
      bankCode: 'AXIS',
      channel: Channel.email,
      name: 'Credit card spend (email)',
      pattern: rx(
        r'Axis Bank Credit Card no\. XX(?<last4>\d{4}) for INR (?<amount>{amt}) at '
        r'(?<payee>.+?) on (?<date>[\d\-]+ [\d:]+)(?: IST)?\. Available limit:? INR (?<balance>{amt})',
      ),
      defaults: const {'direction': 'debit', 'txnType': 'card'},
    ),
    ParserTemplate(
      id: 'axis_email_upi',
      bankCode: 'AXIS',
      channel: Channel.email,
      name: 'UPI debit/credit (email)',
      pattern: rx(
        r'INR (?<amount>{amt}) has been (?<direction>debited|credited) (?:from|to) your '
        r'A/c no\. XX(?<last4>\d{4}) on (?<date>[\d\-]+ [\d:]+)(?: IST)? towards '
        r'UPI/P2[AM]/(?<ref>\d+)/(?<payee>.+?)\.',
      ),
      defaults: const {'txnType': 'upi'},
    ),
  ],
);
