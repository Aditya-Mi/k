import 'package:flutter/material.dart';

/// Shown instead of the app when the database can't be opened. Nothing is
/// deleted or recreated: the data stays on the phone as it was.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.lostKey});

  /// The database is there but its key is gone from secure storage.
  final bool lostKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'k can\'t open your payments',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                lostKey
                    ? 'The key that unlocks your data is missing from this '
                          'phone\'s secure storage. Your data hasn\'t been '
                          'touched. To get it back, clear k\'s storage and '
                          'restore your latest backup.'
                    : 'Something stopped the database from opening. Your '
                          'data hasn\'t been touched. Try closing and '
                          'reopening k.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
