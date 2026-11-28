import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/utils/url_builder.dart';
import '../../domain/campaign_activation_review.dart';
import '../../domain/campaign_wording.dart';
import '../../domain/event_model.dart';

/// C-05: review before a campaign is published. Returns true to publish.
class CampaignActivationSummaryDialog extends StatelessWidget {
  final CampaignActivationReview review;

  const CampaignActivationSummaryDialog({super.key, required this.review});

  static Future<bool> show(BuildContext context, CampaignActivationReview review) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => CampaignActivationSummaryDialog(review: review),
    );
    return ok == true;
  }

  static String _day(DateTime? d) => d == null
      ? 'غير محدد'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final e = review.event;
    final products = e.requiredProducts.where((p) => p.trim().isNotEmpty).toList();
    final slug = e.companySlug.trim();
    final eventId = review.isNew ? null : e.id;

    Widget section(String title, IconData icon, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(title, style: tt.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            Expanded(child: SelectableText(v, style: tt.bodyMedium)),
          ]),
        );

    Color levelColor(ReviewLevel l) => switch (l) {
          ReviewLevel.danger => cs.error,
          ReviewLevel.warning => cs.tertiary,
          ReviewLevel.info => cs.onSurfaceVariant,
        };
    IconData levelIcon(ReviewLevel l) => switch (l) {
          ReviewLevel.danger => Icons.error_outline_rounded,
          ReviewLevel.warning => Icons.warning_amber_rounded,
          ReviewLevel.info => Icons.info_outline_rounded,
        };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(review.isNew ? 'مراجعة قبل تفعيل الحملة' : 'مراجعة قبل حفظ التعديل',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: DefaultTextStyle.merge(
              style: GoogleFonts.cairo(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (review.warnings.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: review.hasDanger ? cs.errorContainer.withValues(alpha: 0.5) : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in review.warnings)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(levelIcon(w.level), size: 18, color: levelColor(w.level)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(w.message,
                                      style: tt.bodyMedium?.copyWith(
                                          color: w.level == ReviewLevel.info ? cs.onSurfaceVariant : levelColor(w.level),
                                          fontWeight: w.level == ReviewLevel.danger ? FontWeight.bold : null)),
                                ),
                              ]),
                            ),
                        ],
                      ),
                    ),
                  section('بيانات الحملة', Icons.campaign_outlined, [
                    kv('اسم الحملة', e.eventName),
                    kv('الشركة', '${e.targetCompany} (${e.companySlug})'),
                    kv('من', _day(e.startDate)),
                    kv('آخر يوم', _day(e.endDate)),
                    kv('السلسلة', e.retailChainName.isEmpty ? '—' : e.retailChainName),
                    kv('الفروع', e.isAllBranches || e.branchNames.isEmpty ? 'كل الفروع' : '${e.branchNames.length} فرع'),
                    kv('طريقة الجائزة', CampaignActivationReview.gameLabel(e.gameType)),
                  ]),
                  section('الشروط', Icons.rule_rounded, [
                    kv('الحد الأدنى للشراء', e.minimumSpend > 0 ? _num(e.minimumSpend) : 'بدون'),
                    kv('منتجات مطلوبة', products.isEmpty ? 'بدون' : products.join('، ')),
                    kv('تعدد الفرص', e.allowMultipleChances ? 'مفعّل (حد أقصى ${e.maxChancesPerReceipt})' : 'فرصة واحدة للفاتورة'),
                    if (e.promotionalRules.isEmpty) kv('القواعد', 'بدون قواعد'),
                    for (final r in e.promotionalRules)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${CampaignActivationReview.describeRule(r)}', style: tt.bodyMedium),
                      ),
                  ]),
                  // TAG-45: stock is shown as plain info only (no red, no
                  // "no stock" line); the section is hidden when empty.
                  if (review.stockByBranch.isNotEmpty)
                  section('الهدايا والرصيد لكل فرع', Icons.inventory_2_outlined, [
                    for (final entry in review.stockByBranch.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(entry.key, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      for (final AllocatedPrize p in entry.value)
                        Text(
                          '   ${CampaignWording.giftLabel(p.name)}: ${p.allocatedQuantity}${review.isNew ? '' : ' (المتبقي ${p.remainingQuantity})'}',
                          style: tt.bodyMedium,
                        ),
                    ],
                    if (review.stockByBranch.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('الإجمالي: ${review.totalAllocated}', style: tt.bodyMedium),
                      ),
                  ]),
                  section('الروابط', Icons.link_rounded, [
                    if (slug.isEmpty)
                      Text('الروابط محتاجة معرّف شركة.', style: tt.bodyMedium?.copyWith(color: cs.error))
                    else ...[
                      kv('المندوب', AppUrlBuilder.buildPromoterUrl(slug, eventId: eventId)),
                      kv('تشغيل الوكالة', AppUrlBuilder.buildAgencyOpsUrl(slug, eventId: eventId)),
                      kv('مدير الحساب', AppUrlBuilder.buildManagerPortalUrl(slug, eventId: eventId)),
                      if (review.isNew)
                        Text('الروابط الخاصة بالحملة نفسها هتظهر بعد تفعيل الحملة.',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('رجوع للتعديل', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: review.hasDanger ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
            child: Text(
              review.hasDanger
                  ? (review.isNew ? 'تفعيل رغم التحذيرات' : 'حفظ رغم التحذيرات')
                  : (review.isNew ? 'تأكيد وتفعيل الحملة' : 'تأكيد وحفظ التعديل'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
