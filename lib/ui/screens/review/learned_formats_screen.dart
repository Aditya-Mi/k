import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart' show Channel, TemplateKind;

import '../../../data/review/learned_formats.dart';
import '../../../di.dart';
import '../../motion.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import 'message_marks.dart';
import 'review_editor_screen.dart';

/// Formats taught in Review: the sample each came from and what it reads.
/// Pause stops it reading new messages; Edit re-marks its sample; Forget
/// removes it. Payments it already logged stay either way.
class LearnedFormatsScreen extends StatelessWidget {
  const LearnedFormatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Learned formats'),
      ),
      body: StreamBuilder<List<LearnedFormat>>(
        stream: getIt<LearnedFormats>().watch(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const SizedBox.shrink();
          if (list.isEmpty) {
            return const Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  title: 'No learned formats',
                  body: 'Formats you teach k in Review appear here.',
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, i) => i == list.length
                ? Text(
                    'Logged payments stay if you pause or forget a format.',
                    style: t.meta.copyWith(color: c.text3),
                  )
                : _FormatCard(format: list[i]),
          );
        },
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format});

  final LearnedFormat format;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final row = format.row;
    final isSms = row.channel == Channel.sms;
    final uses = format.uses;
    final what = switch (row.kind) {
      TemplateKind.ignore => 'skips',
      TemplateKind.mandate => 'AutoPay alert · read',
      TemplateKind.transaction => 'read',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border.all(color: c.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSms ? Icons.sms_outlined : Icons.mail_outline_rounded,
                size: 20,
                color: c.text2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format.sample?.sender ?? format.bankName,
                      style: t.body.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${format.bankName} · learned ${dayMonth(row.createdAt)}'
                      ' · $what $uses ${uses == 1 ? 'message' : 'messages'}',
                      style: t.meta,
                    ),
                  ],
                ),
              ),
              Switch(
                value: row.enabled,
                onChanged: (on) =>
                    getIt<LearnedFormats>().setEnabled(row.id, on),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedOpacity(
              duration: Motion.of(context, Motion.short),
              opacity: row.enabled ? 1 : 0.45,
              child: format.sampleText == null
                  ? Text(
                      'Sample message no longer stored.',
                      style: t.meta.copyWith(color: c.text3),
                    )
                  : MessageMarks(
                      text: format.sampleText!,
                      marks: format.marks,
                      onLongPressWord: (_, _) {},
                      onTapMark: (_) {},
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  row.enabled ? '' : 'Paused · new messages skip it',
                  style: t.meta.copyWith(color: c.text3),
                ),
              ),
              // Re-mark the sample; skip formats have nothing to mark.
              if (format.sample != null && row.kind != TemplateKind.ignore)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReviewEditorScreen(
                        startRawId: format.sample!.id,
                        editTemplateId: row.id,
                      ),
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              TextButton(
                onPressed: () => _forget(context),
                child: const Text('Forget'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _forget(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this format?'),
        content: const Text(
          'Similar messages go to Review again. Logged payments stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok == true) await getIt<LearnedFormats>().forget(format.row.id);
  }
}
