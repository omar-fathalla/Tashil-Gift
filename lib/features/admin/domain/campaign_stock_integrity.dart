import 'event_model.dart';

/// One gift a spend tier can hand out (a reward option, or a linked gift when
/// the tier has no options). Mirrors functions/consuming_spend_ladder.js giftLists.
class TierStockOption {
  final String ruleLabel;
  final String giftId;
  final String label;
  final double value;

  const TierStockOption({
    required this.ruleLabel,
    required this.giftId,
    required this.label,
    required this.value,
  });
}

/// Stock-row integrity checks shared by the campaign editor and the branch
/// balances table. A spend-tier claim draws stock from the row with the
/// tier option's giftId, so an option bound to the wrong giftId (e.g.
/// "voucher 150" pointing at the "voucher 25" id) looks like an empty stock.
class CampaignStockIntegrity {
  CampaignStockIntegrity._();

  static final RegExp _voucherName =
      RegExp(r'فواتشر|فوتشر|فاوتشر|قسيمة|قسائم|voucher|coupon', caseSensitive: false);

  static String _latinDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = ar.indexOf(ch);
      b.write(i >= 0 ? '$i' : ch);
    }
    return b.toString();
  }

  static double firstNumber(String text) {
    final m = RegExp(r'\d+(\.\d+)?').firstMatch(_latinDigits(text));
    return m == null ? 0 : double.tryParse(m.group(0)!) ?? 0;
  }

  /// Face value a stock row stands for (unitValue, else the number in a voucher name).
  static double rowValue(AllocatedPrize p) {
    if (p.unitValue > 0) return p.unitValue;
    if (p.giftType == 'voucher' || _voucherName.hasMatch(p.name)) return firstNumber(p.name);
    return 0;
  }

  /// True when a voucher row's value contradicts the option (only vouchers are compared).
  static bool valueConflicts(TierStockOption option, AllocatedPrize row) {
    final rv = rowValue(row);
    if (rv <= 0) return false;
    var ov = option.value;
    if (ov <= 0 && _voucherName.hasMatch(option.label)) ov = firstNumber(option.label);
    return ov > 0 && (ov - rv).abs() >= 0.01;
  }

  static bool _isSpendTier(PromotionalRuleItem r) => r.conditionType != 'by_quantity' && r.minSpend > 0;

  static String _ruleLabel(PromotionalRuleItem r) {
    final v = r.minSpend == r.minSpend.roundToDouble() ? r.minSpend.toInt().toString() : r.minSpend.toString();
    return 'شريحة $v جنيه';
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Gifts each spend tier can hand out, in the same order the server reads them.
  static List<TierStockOption> tierOptions(List<PromotionalRuleItem> rules) {
    final out = <TierStockOption>[];
    for (final r in rules.where(_isSpendTier)) {
      final label = _ruleLabel(r);
      if (r.rewardOptions.isNotEmpty) {
        for (final o in r.rewardOptions) {
          out.add(TierStockOption(
            ruleLabel: label,
            giftId: o.giftId.trim(),
            label: o.displayLabel,
            value: o.monetaryValue,
          ));
        }
      } else {
        for (final g in r.linkedGifts) {
          out.add(TierStockOption(
            ruleLabel: label,
            giftId: g.giftId.trim(),
            label: g.giftName.trim(),
            value: g.isVoucher ? g.unitValue : 0,
          ));
        }
      }
    }
    return out;
  }

  /// Arabic problems that block saving: a tier option with no stock row of the
  /// same giftId, or whose rows all carry a different voucher value. A campaign
  /// with no stock rows yet (stock fed later / company pool) is not checked
  /// for missing rows. Options without a giftId keep the legacy name match.
  static List<String> tierOptionStockIssues({
    required List<PromotionalRuleItem> rules,
    required List<AllocatedPrize> prizes,
  }) {
    final issues = <String>[];
    final seen = <String>{};
    for (final o in tierOptions(rules)) {
      if (o.giftId.isEmpty) continue;
      final rows = prizes.where((p) => p.giftId.trim() == o.giftId).toList();
      String? issue;
      if (rows.isEmpty) {
        if (prizes.isNotEmpty) {
          issue = '${o.ruleLabel}: الهدية "${o.label}" ليس لها صف رصيد بنفس الهدية في أرصدة الحملة.';
        }
      } else if (rows.every((p) => valueConflicts(o, p))) {
        final row = rows.first;
        issue = '${o.ruleLabel}: الهدية "${o.label}"${o.value > 0 ? ' (${_fmt(o.value)} جنيه)' : ''} '
            'مربوطة برصيد "${row.name}" (${_fmt(rowValue(row))} جنيه).';
      }
      if (issue != null && seen.add(issue)) issues.add(issue);
    }
    return issues;
  }

  /// Full Arabic message for the editor, or null when the tiers are consistent.
  static String? tierOptionStockError({
    required List<PromotionalRuleItem> rules,
    required List<AllocatedPrize> prizes,
  }) {
    final issues = tierOptionStockIssues(rules: rules, prizes: prizes);
    if (issues.isEmpty) return null;
    return 'لا يمكن حفظ الحملة: ربط هدايا الشرائح بالأرصدة غير صحيح، وسيرفض الصرف لهذه الهدايا.\n'
        '${issues.map((e) => '• $e').join('\n')}\n'
        'اختر الهدية الصحيحة في الشريحة أو أضف لها رصيدًا في الفروع.';
  }

  /// Stored remainingQuantity of the rows matching [giftId]/[giftName] in a
  /// branch (the number claims are checked against). Null when no row exists.
  static int? storedRemaining({
    required List<AllocatedPrize> prizes,
    required String giftId,
    required String giftName,
    required bool Function(AllocatedPrize p) branchMatches,
  }) {
    final id = giftId.trim().toLowerCase();
    final name = giftName.trim().toLowerCase();
    int? sum;
    for (final p in prizes) {
      final pid = p.giftId.trim().toLowerCase();
      // Same gift test as the balances table (giftId or exact name).
      final isGift = (id.isNotEmpty && pid == id) || (name.isNotEmpty && p.name.trim().toLowerCase() == name);
      if (isGift && branchMatches(p)) sum = (sum ?? 0) + p.remainingQuantity;
    }
    return sum;
  }

  /// A cell is flagged when a stored row exists and disagrees with the computed remaining.
  static bool remainingMismatch({required int computed, required int? stored}) =>
      stored != null && stored != computed;
}
