// 2.0.171+232: two general post-scan checks used by the rep upload screen.
//  A) price sanity: a target-product line whose unit price is far from the
//     company catalog's `referencePrice` is flagged so the screen can run ONE
//     focused AI re-read before deciding.
//  B) spend near-miss: when the only failing condition is spend and the
//     target total is within 10% below the closest spend threshold, the rep
//     is asked to retake the photo instead of getting a final rejection.
import 'dart:math' as math;

import '../../features/admin/domain/event_model.dart';
import '../services/ai_receipt_service.dart';
import '../services/company_products_service.dart';

class PriceSanityFlag {
  final String name;
  final double unitPrice;
  final double referencePrice;
  final String matchedBy; // 'barcode' | 'name'
  const PriceSanityFlag(this.name, this.unitPrice, this.referencePrice, this.matchedBy);

  double get ratio => referencePrice > 0 ? unitPrice / referencePrice : 1;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': unitPrice,
        'ref': double.parse(referencePrice.toStringAsFixed(2)),
        'by': matchedBy,
      };
}

class ReceiptPriceSanity {
  static const double lowRatio = 0.5;
  static const double highRatio = 2.0;

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[ـ\u064B-\u0652]'), '')
      .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Set<String> tokens(String s) =>
      normalize(s).split(' ').where((t) => t.length >= 2).toSet();

  /// Reference price for [line] from catalog items that carry a
  /// `referencePrice`: an exact barcode match wins; otherwise the median of
  /// catalog items that share the line's rarest catalog word and at least
  /// half of its known words (brand words / "خلطة" alone never match).
  /// Null = no reference.
  static (double, String)? referenceFor(
    ExtractedProductItem line,
    List<CompanyProductItem> catalog, {
    Map<String, int>? docFreq,
  }) {
    final bc = line.barcode.trim();
    if (bc.isNotEmpty) {
      for (final c in catalog) {
        if (c.barcode.trim() == bc && (c.referencePrice ?? 0) > 0) {
          return (c.referencePrice!, 'barcode');
        }
      }
    }
    final df = docFreq ?? documentFrequency(catalog);
    // Known tokens, rarest first. The rarest one (e.g. "فيجيتار", not
    // "كنور"/"خلطة") must be shared, plus at least half of all known tokens.
    final known = tokens(line.name).where((t) => (df[t] ?? 0) > 0).toList()
      ..sort((x, y) => df[x]!.compareTo(df[y]!));
    if (known.isEmpty) return null;
    final key = known.first;
    // Even the rarest word is common (e.g. only "كنور خلطة ...") -> no match.
    if (df[key]! > math.max(3, (catalog.length * 0.03).ceil())) return null;
    final need = (known.length / 2).ceil();
    final prices = <double>[];
    for (final c in catalog) {
      final ref = c.referencePrice ?? 0;
      if (ref <= 0) continue;
      final ct = tokens(c.productName);
      if (!ct.contains(key)) continue;
      if (known.where(ct.contains).length >= need) prices.add(ref);
    }
    if (prices.isEmpty) return null;
    prices.sort();
    final m = prices.length ~/ 2;
    final median = prices.length.isOdd ? prices[m] : (prices[m - 1] + prices[m]) / 2;
    return (median, 'name');
  }

  static Map<String, int> documentFrequency(List<CompanyProductItem> catalog) {
    final df = <String, int>{};
    for (final c in catalog) {
      for (final t in tokens(c.productName)) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    return df;
  }

  /// Target-company lines whose unit price is <50% or >200% of reference.
  static List<PriceSanityFlag> suspiciousLines(
    List<ExtractedProductItem> lines,
    List<CompanyProductItem> catalog,
  ) {
    if (catalog.every((c) => (c.referencePrice ?? 0) <= 0)) return const [];
    final df = documentFrequency(catalog);
    final out = <PriceSanityFlag>[];
    for (final l in lines) {
      if (!l.isTargetCompany || l.price <= 0) continue;
      final ref = referenceFor(l, catalog, docFreq: df);
      if (ref == null) continue;
      final ratio = l.price / ref.$1;
      if (ratio < lowRatio || ratio > highRatio) {
        out.add(PriceSanityFlag(l.name, l.price, ref.$1, ref.$2));
      }
    }
    return out;
  }

  /// Extra prompt for the single focused re-read.
  static String reReadPrompt(List<PriceSanityFlag> flags) {
    final lines = flags
        .map((f) => '- "${f.name}": قرأت السعر ${f.unitPrice}، والسعر المعتاد حوالي ${f.referencePrice.toStringAsFixed(1)}')
        .join('\n');
    return 'تنبيه تدقيق أسعار: الأصناف التالية أسعارها المقروءة بعيدة جداً عن السعر المعتاد، '
        'ربما أُخذ السعر من سطر مجاور. أعد قراءة كل صنف منها بدقة: خذ الكمية وسعر الوحدة '
        'والإجمالي من سطر أرقام الصنف نفسه فقط (نفس السطر الأفقي لاسم الصنف، أو السطر اللي تحت الاسم مباشرة '
        'لو البون بيطبع الاسم في سطر لوحده فوق الأرقام، زي جملة ماركت)، وتأكد أن الكمية × سعر الوحدة = إجمالي السطر. '
        'لا تغيّر السعر إلا لو كان المطبوع فعلاً مختلفاً، ولا تخترع أرقاماً:\n$lines';
  }

  /// The re-read is used only if it has target products and fewer suspicious
  /// lines than the original (i.e. it actually corrected something).
  static bool reReadIsBetter({
    required List<PriceSanityFlag> before,
    required List<PriceSanityFlag> after,
    required AiReceiptAnalysisResult reRead,
  }) {
    final hasTarget = reRead.extractedProducts.any((p) => p.isTargetCompany) ||
        reRead.targetCompanyTotal > 0;
    return hasTarget && after.length < before.length;
  }
}

class SpendNearMiss {
  final String campaignId;
  final String campaignName;
  final String ruleTitle;
  final double total;
  final double threshold;
  const SpendNearMiss(this.campaignId, this.campaignName, this.ruleTitle, this.total, this.threshold);

  double get gap => threshold - total;

  Map<String, dynamic> toJson() => {
        'campaign_id': campaignId,
        'rule': ruleTitle,
        'total': total,
        'threshold': threshold,
        'gap': double.parse(gap.toStringAsFixed(2)),
      };
}

class ReceiptNearMiss {
  static const double window = 0.10;

  /// Closest spend threshold (after tolerance) the [total] misses by at most
  /// 10%, across [campaigns]. Null when any spend threshold is already met
  /// (then spend is not what failed), when nothing is within 10%, or when the
  /// campaigns have no spend thresholds.
  static SpendNearMiss? find({
    required double total,
    required List<EventModel> campaigns,
  }) {
    if (total <= 0) return null;
    SpendNearMiss? best;
    for (final ev in campaigns) {
      final thresholds = <(String, double)>[
        if (ev.minimumSpend > 0) ('minimumSpend', ev.minimumSpend),
        for (final r in ev.promotionalRules)
          if (r.isSpendBased && !r.isCombo && r.effectiveMinSpend > 0)
            (r.ruleTitle, r.effectiveMinSpend),
      ];
      for (final t in thresholds) {
        if (total >= t.$2) return null;
        if (total >= t.$2 * (1 - window)) {
          final c = SpendNearMiss(ev.id, ev.eventName, t.$1, total, t.$2);
          if (best == null || c.gap < best.gap) best = c;
        }
      }
    }
    return best;
  }
}
