import 'company_gift_model.dart';
import 'event_model.dart';

/// TAG-40 (C-02): keeps a campaign's tier gift links pointing at gifts that
/// exist in the company's gift list.
///
///  * a link whose giftId exists is kept as is;
///  * a link found only by name (the gift was re-created or its id changed)
///    gets the current giftId, so the server claim matches the right stock
///    row (TAG-48 matches by giftId first);
///  * a link to a gift that no longer exists is removed;
///  * a rule whose single legacy link (linkedGiftId) points at a removed gift
///    is dropped, as before.
///
/// Nothing is cleaned when [gifts] is empty: an empty list may only mean the
/// gifts did not load, and wiping every link then would lose data.
class LinkedGiftCleanup {
  LinkedGiftCleanup._();

  static List<PromotionalRuleItem> reconcile(List<PromotionalRuleItem> rules, List<CompanyGiftModel> gifts) {
    if (gifts.isEmpty) return rules;
    final byId = {for (final g in gifts) g.id: g};
    final out = <PromotionalRuleItem>[];
    for (final rule in rules) {
      final legacyId = rule.linkedGiftId ?? '';
      if (legacyId.isNotEmpty &&
          !byId.containsKey(legacyId) &&
          !gifts.any((g) => g.giftName == rule.linkedGiftName)) {
        continue;
      }
      final links = <LinkedGiftAllocation>[];
      for (final lg in rule.linkedGifts) {
        if (byId.containsKey(lg.giftId)) {
          links.add(lg);
          continue;
        }
        final byName = gifts.where((g) => g.giftName == lg.giftName).toList();
        if (byName.length == 1) links.add(lg.copyWith(giftId: byName.single.id));
        // No gift, or the name is ambiguous: the link is dead.
      }
      out.add(rule.copyWith(linkedGifts: links));
    }
    return out;
  }

  /// Links in [rules] that [reconcile] would change or remove (for reports).
  static int deadLinks(List<PromotionalRuleItem> rules, List<CompanyGiftModel> gifts) {
    final ids = {for (final g in gifts) g.id};
    return rules.fold(0, (n, r) => n + r.linkedGifts.where((lg) => !ids.contains(lg.giftId)).length);
  }
}
