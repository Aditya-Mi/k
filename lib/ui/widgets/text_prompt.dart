import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/k_theme.dart';

/// One-field text dialog. Returns the text on confirm, null on cancel.
///
/// The dialog owns its controller so it is disposed with the dialog, not when
/// `showDialog` returns (the field is still mounted during the exit animation).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? help,
  String action = 'Save',
  bool numeric = false,
  int maxLines = 1,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    initial: initial,
    hint: hint,
    help: help,
    action: action,
    numeric: numeric,
    maxLines: maxLines,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.hint,
    required this.help,
    required this.action,
    required this.numeric,
    required this.maxLines,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? help;
  final String action;
  final bool numeric;
  final int maxLines;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      autofocus: true,
      maxLines: widget.maxLines,
      minLines: 1,
      keyboardType: widget.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (widget.maxLines > 1
                ? TextInputType.multiline
                : TextInputType.text),
      inputFormatters: widget.numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))]
          : null,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixText: widget.numeric ? '₹ ' : null,
      ),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: widget.help == null
          ? field
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field,
                const SizedBox(height: 8),
                Text(widget.help!, style: context.kt.meta),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
