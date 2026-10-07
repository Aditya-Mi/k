import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../data/db/app_database.dart' hide ParserTemplate, SenderRule;
import '../../data/email/readable_text.dart';
import '../format.dart';
import '../theme/k_theme.dart';

/// The bank message verbatim (emails tidied for reading). Secondary sources of a merged transaction carry
/// a MERGED stamp (The Struck Not Gone Rule).
class RawMessageCard extends StatelessWidget {
  const RawMessageCard({super.key, required this.message, this.merged = false});

  final RawMessage message;
  final bool merged;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final isSms = message.channel == Channel.sms;
    final sim = message.simSlot == null ? '' : ' · SIM ${message.simSlot! + 1}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border.all(color: c.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  isSms ? Symbols.sms : Symbols.mail,
                  size: 20,
                  color: c.text2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.sender,
                      style: t.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${isSms ? 'SMS' : 'Email'} · '
                      '${dayMonth(message.receivedAt)}, ${hhmm(message.receivedAt)}$sim',
                      style: t.meta,
                    ),
                  ],
                ),
              ),
              if (merged) const _MergedStamp(),
            ],
          ),
          const SizedBox(height: 12),
          if (message.subject != null) ...[
            SelectableText(
              message.subject!,
              style: t.body.copyWith(color: c.text2),
            ),
            const SizedBox(height: 4),
          ],
          SelectableText(
            message.channel == Channel.email
                ? readableEmail(message.body)
                : message.body.trim(),
            style: t.body.copyWith(color: c.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _MergedStamp extends StatelessWidget {
  const _MergedStamp();

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: c.text2, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'MERGED',
          style: context.kt.label.copyWith(
            letterSpacing: 2.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
