import 'package:meta/meta.dart';

import 'enums.dart';
import 'template.dart';

/// Adding a bank = one BankDefinition + its fixtures, then register it.
@immutable
class BankDefinition {
  const BankDefinition({
    required this.code,
    required this.name,
    required this.smsSenders,
    required this.emailSenders,
    required this.templates,
    this.kind = InstitutionKind.bank,
  });

  final String code;
  final String name;

  /// Header cores, e.g. 'AXISBK' matches 'AX-AXISBK-S'.
  final List<String> smsSenders;

  /// Full addresses or domains, e.g. 'axisbank.com'.
  final List<String> emailSenders;
  final List<ParserTemplate> templates;
  final InstitutionKind kind;

  List<SenderRule> get senderRules => [
    for (final p in smsSenders) SenderRule(code, Channel.sms, p),
    for (final p in emailSenders) SenderRule(code, Channel.email, p),
  ];
}

@immutable
class SenderRule {
  const SenderRule(this.bankCode, this.channel, this.pattern);

  final String bankCode;
  final Channel channel;
  final String pattern;

  bool matches(Channel ch, String sender) {
    if (ch != channel) return false;
    if (ch == Channel.sms) {
      return sender.toUpperCase().contains(pattern.toUpperCase());
    }
    final address = _emailAddress(sender);
    final p = pattern.toLowerCase();
    if (p.contains('@')) return address == p;
    final domain = address.split('@').last;
    return domain == p || domain.endsWith('.$p');
  }

  /// `Axis Bank <Alerts@AxisBank.com>` → `alerts@axisbank.com`.
  static String _emailAddress(String from) {
    final m = RegExp(r'<([^>]+)>').firstMatch(from);
    return (m?.group(1) ?? from).trim().toLowerCase();
  }
}
