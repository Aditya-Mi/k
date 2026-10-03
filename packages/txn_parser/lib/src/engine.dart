import 'bank_definition.dart';
import 'enums.dart';
import 'field_mapping.dart';
import 'generic_fallback.dart';
import 'normalizers/amount.dart';
import 'normalizers/date.dart';
import 'normalizers/merchant.dart';
import 'normalizers/text.dart';
import 'parse_result.dart';
import 'prefilters.dart';
import 'raw_input.dart';
import 'template.dart';

/// Pipeline: bank classify → prefilter → template match → normalize.
class ParserEngine {
  ParserEngine({
    required List<BankDefinition> banks,
    List<SenderRule>? senderRules,
    List<ParserTemplate> userTemplates = const [],
  }) : _senderRules = senderRules ?? [for (final b in banks) ...b.senderRules],
       _templates = [
         ...userTemplates,
         for (final b in banks) ...b.templates,
       ]..sort((a, b) => a.priority.compareTo(b.priority));

  /// Configurable in Settings; defaults to the bank definitions' senders.
  final List<SenderRule> _senderRules;
  final List<ParserTemplate> _templates;

  String? identifyBank(Channel channel, String sender) {
    for (final rule in _senderRules) {
      if (rule.matches(channel, sender)) return rule.bankCode;
    }
    return null;
  }

  ParseResult parse(RawInput input) {
    final bank = identifyBank(input.channel, input.sender);
    if (bank == null) return const ParseResult(status: ParseStatus.notBank);

    final text = normalizeText(
      [?input.subject, input.body].join(' '),
    );

    final reason = nonTransactionReason(text);
    if (reason != null) {
      return ParseResult(
        status: ParseStatus.nonTransaction,
        bankCode: bank,
        note: reason,
      );
    }

    for (final template in _candidates(bank, input.channel)) {
      final match = template.regex.firstMatch(text);
      if (match == null) continue;
      if (template.kind == TemplateKind.ignore) {
        return ParseResult(
          status: ParseStatus.nonTransaction,
          bankCode: bank,
          kind: TemplateKind.ignore,
          templateId: template.id,
          note: 'ignore template',
        );
      }
      return _fromMatch(bank, template, match, text, input.receivedAt);
    }

    return ParseResult(
      status: ParseStatus.needsReview,
      bankCode: bank,
      fields: guessFields(text),
      missing: const ['template'],
      note: 'no template matched',
    );
  }

  /// Email alerts often reuse the SMS sentence, so SMS templates are
  /// a fallback for email (never the other way round).
  Iterable<ParserTemplate> _candidates(String bank, Channel channel) sync* {
    yield* _templates.where((t) => t.bankCode == bank && t.channel == channel);
    if (channel == Channel.email) {
      yield* _templates.where(
        (t) => t.bankCode == bank && t.channel == Channel.sms,
      );
    }
  }

  ParseResult _fromMatch(
    String bank,
    ParserTemplate template,
    RegExpMatch match,
    String text,
    DateTime receivedAt,
  ) {
    String? group(String name) {
      if (!match.groupNames.contains(name)) {
        return template.defaults[name];
      }
      final v = match.namedGroup(name)?.trim();
      return (v == null || v.isEmpty) ? template.defaults[name] : v;
    }

    final isMandate = template.kind == TemplateKind.mandate;
    final amount = group(Fields.amount);
    final balance = group(Fields.balance);
    final date = group(Fields.date);
    final dueDate = group(Fields.dueDate);
    final payee = group(Fields.payee);

    final fields = ParsedFields(
      amountMinor: amount == null ? null : parseAmountMinor(amount),
      currency: group(Fields.currency)?.toUpperCase() ?? 'INR',
      direction:
          directionFromWord(group(Fields.direction)) ??
          (isMandate ? Direction.debit : null),
      txnType:
          txnTypeFromWord(group(Fields.type)) ??
          txnTypeFromWord(template.defaults['txnType']) ??
          inferTxnType(text, isMandate: isMandate),
      last4: group(Fields.last4),
      payee: payee == null ? null : cleanPayee(payee),
      ref: group(Fields.ref),
      occurredAt: resolveOccurredAt(
        date == null ? null : parseBankDate(date),
        receivedAt,
      ),
      balanceMinor: balance == null ? null : parseAmountMinor(balance),
      dueDate: dueDate == null ? null : parseBankDate(dueDate)?.value,
      mandateRef: group(Fields.mandateRef),
    );

    final missing = [
      if (fields.amountMinor == null) Fields.amount,
      if (fields.direction == null) Fields.direction,
    ];
    return ParseResult(
      status: missing.isEmpty ? ParseStatus.parsed : ParseStatus.needsReview,
      bankCode: bank,
      kind: template.kind,
      templateId: template.id,
      fields: fields,
      missing: missing,
    );
  }
}
