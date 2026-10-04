// Banks and sender rules are seeded from txn_parser's builtInBanks so the
// parser stays the single source of truth for bank definitions.

/// id, name, Material icon, ARGB color.
const seedCategories = [
  ('cat_food', 'Food & Dining', 'restaurant', 0xFFE07A5F),
  ('cat_groceries', 'Groceries', 'shopping_basket', 0xFF81B29A),
  ('cat_shopping', 'Shopping', 'shopping_bag', 0xFFF2CC8F),
  ('cat_travel', 'Travel', 'flight', 0xFF3D85C6),
  ('cat_fuel', 'Fuel', 'local_gas_station', 0xFF8D6E63),
  ('cat_bills', 'Bills & Utilities', 'receipt_long', 0xFF6D597A),
  ('cat_subscriptions', 'Subscriptions', 'autorenew', 0xFFB56576),
  ('cat_entertainment', 'Entertainment', 'movie', 0xFFE56B6F),
  ('cat_health', 'Health', 'medical_services', 0xFF2A9D8F),
  ('cat_education', 'Education', 'school', 0xFF457B9D),
  ('cat_investments', 'Investments', 'trending_up', 0xFF588157),
  ('cat_transfers', 'Transfers', 'swap_horiz', 0xFF6C757D),
  ('cat_cash', 'ATM withdrawal', 'local_atm', 0xFF9C6644),
  ('cat_income', 'Income', 'payments', 0xFF2D6A4F),
  ('cat_uncategorized', 'Uncategorized', 'help_outline', 0xFFADB5BD),
];

const seedKeywords = {
  'cat_food': [
    'swiggy', 'zomato', 'dominos', 'mcdonalds', 'kfc', 'pizza hut', //
    'starbucks', 'burger king', 'eatsure', 'faasos', 'haldiram', 'chaayos',
    'box8',
  ],
  'cat_groceries': [
    'bigbasket', 'blinkit', 'zepto', 'instamart', 'dmart', 'jiomart', //
    'reliance fresh', 'natures basket',
  ],
  'cat_shopping': [
    'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq', //
    'croma', 'reliance digital', 'decathlon', 'ikea', 'lenskart',
  ],
  'cat_travel': [
    'uber', 'ola', 'rapido', 'irctc', 'makemytrip', 'goibibo', 'cleartrip', //
    'indigo', 'air india', 'akasa', 'redbus', 'ixigo', 'yatra', 'metro',
    'fastag',
  ],
  'cat_fuel': [
    'indian oil', 'iocl', 'bpcl', 'bharat petroleum', 'hpcl', //
    'hindustan petroleum', 'shell',
  ],
  'cat_bills': [
    'airtel', 'jio', 'vodafone', 'bsnl', 'tata power', 'adani electricity', //
    'bescom', 'msedcl', 'electricity', 'mahanagar gas', 'igl', 'act fibernet',
    'tata play', 'lic', 'insurance',
  ],
  'cat_subscriptions': [
    'netflix', 'spotify', 'prime video', 'hotstar', 'jiohotstar', //
    'youtube premium', 'google one', 'apple com', 'icloud', 'sonyliv', 'zee5',
    'openai', 'chatgpt', 'anthropic', 'claude', 'github', 'notion',
    'linkedin', 'microsoft', 'adobe',
  ],
  'cat_entertainment': [
    'bookmyshow', 'pvr', 'inox', 'district', 'steam', 'playstation', //
  ],
  'cat_health': [
    'apollo', 'pharmeasy', 'tata 1mg', 'netmeds', 'practo', 'medplus', //
    'cultfit', 'hospital', 'clinic',
  ],
  'cat_education': ['udemy', 'coursera', 'unacademy'],
  'cat_investments': [
    'zerodha', 'groww', 'upstox', 'kuvera', 'indmoney', 'mutual fund', 'nps', //
  ],
};

/// Device-agnostic defaults (approved 2026-10-04).
const seedSettings = {
  'dedup.windowMinutes': '10',
  'subscriptions.amountTolerancePct': '10',
  'subscriptions.reminderDays': '3',
  'email.syncIntervalMinutes': '60',
  'backup.drive.intervalHours': '24',
  'backup.drive.keepCount': '7',
};
