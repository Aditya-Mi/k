import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import 'data/db/app_database.dart';
import 'di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const KApp());
}

class KApp extends StatelessWidget {
  const KApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'k',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const _DbStatusScreen(),
    );
  }
}

/// Phase 1 placeholder: proves the encrypted DB opens and seeds ran.
class _DbStatusScreen extends StatelessWidget {
  const _DbStatusScreen();

  Future<String> _status() async {
    final db = getIt<AppDatabase>();
    final cipher = await db.customSelect('PRAGMA cipher;').getSingle();
    final categories = await db.categories.count().getSingle();
    final rules = await db.categoryRules.count().getSingle();
    return 'cipher: ${cipher.data.values.first}\n'
        'categories: $categories\nkeyword rules: $rules';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('k')),
      body: Center(
        child: FutureBuilder(
          future: _status(),
          builder: (context, snap) => Text(
            snap.hasError ? 'DB error: ${snap.error}' : (snap.data ?? '…'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
