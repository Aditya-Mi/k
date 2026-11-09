// QA audit: a second tap on Save before the first finished must not log
// the payment twice.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/di.dart';
import 'package:k/ui/screens/transactions/add_payment_screen.dart';
import 'package:k/ui/theme/k_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    getIt
      ..registerSingleton<LedgerRepository>(LedgerRepository(db))
      ..registerSingleton<IngestionService>(IngestionService(db));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  testWidgets('Add payment: Save tapped twice logs one payment', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const AddPaymentScreen(),
        ),
      );
      // Accounts load, then the amount prompt opens.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), '500');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump(const Duration(seconds: 1));

      // Only Cash is in k: it is picked already.
      expect(find.text('Cash'), findsOneWidget);

      final save = find.text('Save payment');
      expect(save, findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(of: save, matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(button.onPressed, isNotNull, reason: 'Save is enabled');
      // Two taps, no frame between them.
      await tester.tap(save);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      await tester.pump();
    });
    final rows = await tester.runAsync(
      () => (db.select(db.transactions)).get(),
    );
    expect(rows, hasLength(1));
  });
}
