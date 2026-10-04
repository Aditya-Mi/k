import '../db/app_database.dart';
import '../db/enums.dart';

import 'package:txn_parser/txn_parser.dart' show TxnType;

const uncategorizedId = 'cat_uncategorized';

/// "ATM withdrawal" (was "Cash"; id kept so nothing moves).
const atmCategoryId = 'cat_cash';

/// Picks a category for a payee: merchant rules first (exact merchant key),
/// then keywords on word boundaries, longest keyword winning
/// ("jiomart" beats "jio"). Priority breaks ties before length.
class CategoryResolver {
  CategoryResolver(List<CategoryRule> rules)
    : _merchant = {
        // Ascending priority: a higher-priority rule overwrites a lower one.
        for (final r
            in rules
                .where((r) => r.matchType == RuleMatchType.merchant)
                .toList()
              ..sort((a, b) => a.priority.compareTo(b.priority)))
          r.pattern: r.categoryId,
      },
      _keywords =
          rules
              .where((r) => r.matchType == RuleMatchType.keyword)
              .map((r) => (r.pattern.toLowerCase(), r.categoryId, r.priority))
              .toList()
            ..sort((a, b) {
              final p = b.$3.compareTo(a.$3);
              return p != 0 ? p : b.$1.length.compareTo(a.$1.length);
            });

  static Future<CategoryResolver> load(AppDatabase db) async =>
      CategoryResolver(
        await (db.select(
          db.categoryRules,
        )..where((r) => r.deletedAt.isNull())).get(),
      );

  final Map<String, String> _merchant;
  final List<(String, String, int)> _keywords;

  static final _nonAlnum = RegExp(r'[^a-z0-9]+');

  String resolve({String? merchantKey, String? payee, TxnType? txnType}) {
    // Cash out of an ATM is its own category whatever the "payee" reads.
    if (txnType == TxnType.atm) return atmCategoryId;
    if (merchantKey != null) {
      final hit = _merchant[merchantKey];
      if (hit != null) return hit;
    }
    if (payee == null || payee.isEmpty) return uncategorizedId;

    final lower = payee.toLowerCase();
    // Spaced haystack so " zepto " matches on word boundaries.
    final words = ' ${lower.replaceAll(_nonAlnum, ' ').trim()} ';
    // VPA handles glue words together ("zeptonowcashfree@hdfcbank").
    final handle = lower.contains('@') ? lower.split('@').first : null;

    for (final (keyword, categoryId, _) in _keywords) {
      if (words.contains(' $keyword ')) return categoryId;
      if (handle != null && keyword.length >= 5 && handle.contains(keyword)) {
        return categoryId;
      }
    }
    return uncategorizedId;
  }
}
