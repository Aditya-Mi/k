import 'package:flutter/material.dart';

/// Start day for an inbox import; defaults to the 1st of this month.
Future<DateTime?> pickImportStart(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    helpText: 'Import messages from',
    initialDate: initial ?? DateTime(now.year, now.month),
    firstDate: DateTime(now.year - 3),
    lastDate: now,
  );
}
