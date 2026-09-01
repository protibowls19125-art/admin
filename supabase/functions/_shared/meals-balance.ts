// Decides which way (if any) meals_remaining should move for a meal
// confirmation status change. Used by both whatsapp-webhook (member's own
// reply) and admin-confirm-meal (manager's manual override) so a manual
// override counts identically to a real reply — same decision table, one
// place to get it right.
//
//   YES, wasn't already confirmed → -mealsPerDay (claiming a fresh meal)
//   NO,  was previously confirmed → +mealsPerDay (returning a reversed meal)
//   anything else                 → 0 (no real transition happened)
//
// isYes/isNo are taken separately, not derived from each other — a WhatsApp
// reply has a real third state (ambiguous free text, neither yes nor no)
// that must resolve to 0, not silently fall into the "no" branch.

export function mealsRemainingDelta(
  isYes: boolean,
  isNo: boolean,
  wasConfirmed: boolean,
  mealsPerDay: number,
): number {
  if (isYes && !wasConfirmed) return -mealsPerDay;
  if (isNo && wasConfirmed) return mealsPerDay;
  return 0;
}
