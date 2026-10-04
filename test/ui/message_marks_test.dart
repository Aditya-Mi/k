import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/review/field_marks.dart';
import 'package:k/ui/screens/review/message_marks.dart';
import 'package:k/ui/theme/k_theme.dart';

void main() {
  const text =
      'INR 50,000.00 credited to A/c no. XX0640 on 03-10-26. '
      'Info- NEFT/IN827459235/FOOTPRINTSCHILDHOODEDUCATIONPRIVATELIMITEDVIEW. '
      'Avl Bal- INR 1,12,000.50. Not you? Call 18001035577 - Axis Bank';
  final info = text.indexOf('Info-');

  for (final marks in [
    <FieldMark>[],
    [FieldMark(MarkField.payee, info, info + 80)],
  ]) {
    testWidgets('long words wrap, ${marks.length} marks', (tester) async {
      tester.view.physicalSize = const Size(300 * 2.625, 1600);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: MessageMarks(
                text: text,
                marks: marks,
                onLongPressWord: (_, _) {},
                onTapMark: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
