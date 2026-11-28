/// TAG-88: the campaign-level minimum-spend gate on the upload screen.
///
/// A spend rule's discount tolerance lowers its own threshold
/// (`PromotionalRuleItem.effectiveMinSpend`, e.g. 200 - 5 = 195). The
/// campaign `minimumSpend` gate must honour that too, otherwise a 199 EGP
/// receipt is rejected before the rules (and the server, which already applies
/// the tolerance) ever see it.
library;

import '../../admin/domain/event_model.dart';

/// The threshold the campaign-level gate compares the target-company total
/// against. `0` (or less) means "no gate", exactly like `minimumSpend <= 0`.
///
/// When the campaign has a minimum, the gate is the lowest of that minimum and
/// the tolerance-adjusted minimum of every spend rule (rules without a
/// positive minimum are ignored).
double campaignMinSpendGate(double minimumSpend, Iterable<PromotionalRuleItem> rules) {
  if (minimumSpend <= 0) return minimumSpend;
  var gate = minimumSpend;
  for (final r in rules) {
    if (!r.isSpendBased) continue;
    final s = r.effectiveMinSpend;
    if (s > 0 && s < gate) gate = s;
  }
  return gate;
}
