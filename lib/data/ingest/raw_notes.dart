import 'unknown_sender.dart' show notABankNote;

/// parseNote of a message the owner marked "Not a transaction" in Review.
/// With [notABankNote], the owner's own rejects; every other
/// non-transaction note is an automatic skip (Settings → Skipped messages).
const userRejectedNote = 'marked not a transaction';

/// parseNote of a skipped message the owner sent back to Review; the
/// startup re-check leaves it there.
const sentToReviewNote = 'sent to review';

/// parseNote of an email alert that names no amount.
const noAmountNote = 'email without an amount';

/// Notes of the owner's own rejects, kept out of Skipped messages.
const ownerRejectNotes = [userRejectedNote, notABankNote];
