import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/animations/m3_motion.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/widgets/interactive_receipt_viewer_dialog.dart';

class ValidationConditionItem {
  final String title;
  final String description;
  final IconData icon;
  final bool isMet;
  final String? value;

  const ValidationConditionItem({
    required this.title,
    required this.description,
    required this.icon,
    this.isMet = false,
    this.value,
  });
}

IconData _getConditionIcon(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('كعب') || lower.contains('باركود') || lower.contains('خزينة') || lower.contains('pos') || lower.contains('ماكينة') || lower.contains('توقيت')) {
    return Icons.qr_code_scanner_rounded;
  }
  if (lower.contains('واضحة') || lower.contains('مطموس') || lower.contains('مقروء') || lower.contains('تصوير') || lower.contains('كاميرا') || lower.contains('باهت')) {
    return Icons.camera_alt_rounded;
  }
  if (lower.contains('فرع') || lower.contains('سلسلة') || lower.contains('متجر')) {
    return Icons.storefront_rounded;
  }
  if (lower.contains('تاريخ') || lower.contains('فترة') || lower.contains('يوم')) {
    return Icons.calendar_month_rounded;
  }
  if (lower.contains('مبلغ') || lower.contains('حد أدنى') || lower.contains('إنفاق') || lower.contains('قيمة')) {
    return Icons.price_check_rounded;
  }
  return Icons.rule_folder_rounded;
}

String _getConditionCategoryTitle(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('كعب') || lower.contains('باركود') || lower.contains('خزينة') || lower.contains('pos') || lower.contains('ماكينة')) {
    return 'بيانات كعب الفاتورة';
  }
  if (lower.contains('واضحة') || lower.contains('مطموس') || lower.contains('مقروء') || lower.contains('تصوير') || lower.contains('كاميرا')) {
    return 'وضوح وتصوير الفاتورة';
  }
  if (lower.contains('فرع') || lower.contains('سلسلة') || lower.contains('متجر')) {
    return 'السلسلة والفرع المعتمد';
  }
  if (lower.contains('تاريخ') || lower.contains('فترة') || lower.contains('يوم')) {
    return 'تاريخ الشراء وفترة الحملة';
  }
  if (lower.contains('مبلغ') || lower.contains('حد أدنى') || lower.contains('إنفاق') || lower.contains('قيمة')) {
    return 'الحد الأدنى للمشتريات';
  }
  return 'شرط غير مستوفى';
}

/// Helper to compile all unfulfilled conditions into a structured list
List<ValidationConditionItem> buildValidationConditionItems({
  required bool isValid,
  required String message,
  required double targetCompanyTotal,
  required double minimumSpend,
  required String targetCompany,
  required String currencySymbol,
  List<String> unfulfilledConditions = const [],
  bool isBranchMatched = true,
  String storeChainDetected = '',
  String branchDetected = '',
  String retailChainName = '',
  List<String> allowedBranches = const [],
  bool isAllBranches = true,
  String receiptDate = '',
  bool hasTargetProducts = true,
  bool isHandwritten = false,
  bool isThermalPosReceipt = true,
  bool isTampered = false,
  bool isScreenCapture = false,
  List<String> fraudReasons = const [],
}) {
  final items = <ValidationConditionItem>[];

  if (isHandwritten || message.contains('محررة يدوياً') || message.contains('محررة بخط اليد') || fraudReasons.any((r) => r.contains('يدوي') || r.contains('خط اليد'))) {
    items.add(
      const ValidationConditionItem(
        title: 'فاتورة محررة يدوياً',
        description: 'الفاتورة محررة بخط اليد وليست بون كاشير إلكتروني مطبوع من طابعات نقاط البيع (POS).',
        icon: Icons.edit_note_rounded,
        isMet: false,
      ),
    );
  } else if (isTampered || fraudReasons.any((r) => r.contains('شطب') || r.contains('تلاعب'))) {
    items.add(
      const ValidationConditionItem(
        title: 'اشتباه في تلاعب أو شطب وتعديل يدوي',
        description: 'تم رصد شطب أو تعديل يدوي في أرقام أو أسعار الفاتورة المطبوعة.',
        icon: Icons.gavel_rounded,
        isMet: false,
      ),
    );
  } else if (isScreenCapture || message.contains('شاشة إلكترونية') || fraudReasons.any((r) => r.contains('شاشة'))) {
    items.add(
      const ValidationConditionItem(
        title: 'صورة ملتقطة من شاشة إلكترونية',
        description: 'تم رصد تصوير الفاتورة من شاشة هاتف أو حاسوب آخر. يرجى تصوير أصل الفاتورة الورقية مباشرة.',
        icon: Icons.phone_android_rounded,
        isMet: false,
      ),
    );
  } else if (!isThermalPosReceipt || message.contains('ليس بون كاشير')) {
    items.add(
      const ValidationConditionItem(
        title: 'نوع الإيصال غير معتمد',
        description: 'المستند المرفوع ليس بون كاشير إلكتروني مطبوع من ماكينات نقاط البيع المعتمدة.',
        icon: Icons.receipt_long_rounded,
        isMet: false,
      ),
    );
  }

  // 1. Products inclusion condition (Priority 1 if no target products found)
  if (!hasTargetProducts || targetCompanyTotal <= 0) {
    items.add(
      ValidationConditionItem(
        title: 'المنتجات المؤهلة للعرض',
        description: 'لم يتم العثور على أي منتجات تابعة لشركة "$targetCompany" داخل أصناف الفاتورة.',
        icon: Icons.remove_shopping_cart_rounded,
        isMet: false,
      ),
    );
  } else if (minimumSpend > 0 && targetCompanyTotal < minimumSpend) {
    // 2. Minimum Spend Condition (Only if target products DO exist, but spend is below minimum)
    items.add(
      ValidationConditionItem(
        title: 'الحد الأدنى لقيمة المشتريات',
        description: 'إجمالي مشتريات منتجات $targetCompany في الفاتورة ($targetCompanyTotal $currencySymbol) أقل من الحد الأدنى لدخول العرض ($minimumSpend $currencySymbol).',
        icon: Icons.price_check_rounded,
        isMet: false,
        value: '$targetCompanyTotal / $minimumSpend $currencySymbol',
      ),
    );
  }

  // 2. Retail Chain & Branch Condition
  bool isChainMatched = true;
  if (retailChainName.trim().isNotEmpty && storeChainDetected.trim().isNotEmpty) {
    final allowedChains = retailChainName
        .split(RegExp(r'[\•\,\،\/\-\|\+]'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    final detChainNorm = storeChainDetected.trim().toLowerCase();

    isChainMatched = allowedChains.isEmpty || allowedChains.any((ac) {
      return detChainNorm.contains(ac) ||
             ac.contains(detChainNorm) ||
             (detChainNorm.contains('جملة') && ac.contains('جملة')) ||
             (detChainNorm.contains('فتح') && ac.contains('فتح')) ||
             (detChainNorm.contains('كارفور') && ac.contains('كارفور')) ||
             (detChainNorm.contains('سبينس') && ac.contains('سبينس')) ||
             (detChainNorm.contains('خير') && ac.contains('خير'));
    });
  }

  if (!isBranchMatched || !isChainMatched) {
    final allowed = isAllBranches || allowedBranches.isEmpty
        ? (retailChainName.isNotEmpty ? 'كافة فروع $retailChainName' : 'جميع الفروع')
        : allowedBranches.join('، ');
    items.add(
      ValidationConditionItem(
        title: 'السلسلة التجارية والفرع المعتمد',
        description: 'الفاتورة تابعة لـ (${storeChainDetected.isNotEmpty ? storeChainDetected : "غير محدد"} - ${branchDetected.isNotEmpty ? branchDetected : "غير محدد"}). الفروع المعتمدة للعرض: [$allowed].',
        icon: Icons.storefront_rounded,
        isMet: false,
      ),
    );
  }

  // 4. Date condition check
  if (message.contains('تاريخ') || message.contains('فترة') || message.contains('منتهي') || message.contains('سابق') || message.contains('لاحق')) {
    items.add(
      ValidationConditionItem(
        title: 'تاريخ الشراء وفترة الحملة',
        description: 'تاريخ الشراء بالفاتورة (${receiptDate.isNotEmpty ? receiptDate : "غير محدد"}) خارج الفترة الزمنية المعتمدة للعرض الترويجي.',
        icon: Icons.calendar_month_rounded,
        isMet: false,
      ),
    );
  }

  // 5. AI detected specific conditions (Deduplicated & Cleaned)
  final seenNormalized = <String>{};
  for (final cond in unfulfilledConditions) {
    final trimmed = cond.trim();
    if (trimmed.isEmpty) continue;

    final norm = trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    // If no target products exist, skip redundant spend or missing products phrases
    if ((!hasTargetProducts || targetCompanyTotal <= 0) &&
        (norm.contains('لا توجد منتجات') ||
         norm.contains('لم يتم العثور') ||
         norm.contains('أقل من الحد الأدنى') ||
         norm.contains('الحد الادنى') ||
         norm.contains('0 ج.م') ||
         norm.contains('0ج.م') ||
         norm.contains('المشروطة في الفاتورة'))) {
      continue;
    }

    // If spend condition is already covered, skip redundant spend phrases
    if (targetCompanyTotal > 0 &&
        targetCompanyTotal < minimumSpend &&
        (norm.contains('أقل من الحد الأدنى') || norm.contains('الحد الادنى'))) {
      continue;
    }

    // Skip if already in items
    if (items.any((i) => i.description.contains(trimmed) || trimmed.contains(i.description) || trimmed.contains(i.title))) {
      continue;
    }

    if (seenNormalized.contains(norm)) continue;
    seenNormalized.add(norm);

    items.add(
      ValidationConditionItem(
        title: _getConditionCategoryTitle(trimmed),
        description: trimmed,
        icon: _getConditionIcon(trimmed),
        isMet: false,
      ),
    );
  }

  // 6. Fallback if no specific condition was added
  if (items.isEmpty && (!isValid || message.isNotEmpty)) {
    items.add(
      ValidationConditionItem(
        title: 'نتيجة التدقيق والتحقق',
        description: message.isNotEmpty ? message : 'الفاتورة غير مطابقة للشروط والأحكام الخاصة بالعرض.',
        icon: Icons.report_problem_rounded,
        isMet: false,
      ),
    );
  }

  return items;
}

/// Displays an M3-compliant, Purple-themed, structured Receipt Validation Failure Dialog
Future<void> showReceiptValidationReportDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<ValidationConditionItem> conditions,
  String? receiptNumber,
  String? storeChain,
  String? branch,
  String? receiptDate,
  double? totalValue,
  double? requiredMinimum,
  String? currencySymbol,
  String? imageUrl,
  List<String>? imageUrls,
  bool isDuplicate = false,
  VoidCallback? onClose,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'ReceiptValidationReport',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (context, anim1, anim2, child) {
      final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: curved,
        child: FadeTransition(opacity: anim1, child: child),
      );
    },
    pageBuilder: (context, anim1, anim2) {
      return ReceiptValidationReportDialog(
        title: title,
        subtitle: subtitle,
        conditions: conditions,
        receiptNumber: receiptNumber,
        storeChain: storeChain,
        branch: branch,
        receiptDate: receiptDate,
        totalValue: totalValue,
        requiredMinimum: requiredMinimum,
        currencySymbol: currencySymbol,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        isDuplicate: isDuplicate,
        onClose: onClose,
      );
    },
  );
}

class ReceiptValidationReportDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<ValidationConditionItem> conditions;
  final String? receiptNumber;
  final String? storeChain;
  final String? branch;
  final String? receiptDate;
  final double? totalValue;
  final double? requiredMinimum;
  final String? currencySymbol;
  final String? imageUrl;
  final List<String>? imageUrls;
  final bool isDuplicate;
  final VoidCallback? onClose;

  const ReceiptValidationReportDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.conditions,
    this.receiptNumber,
    this.storeChain,
    this.branch,
    this.receiptDate,
    this.totalValue,
    this.requiredMinimum,
    this.currencySymbol,
    this.imageUrl,
    this.imageUrls,
    this.isDuplicate = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final curr = currencySymbol ?? 'ج.م';
    final currentLocale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'ar';
    final strings = AppStrings.fromLocale(currentLocale);

    return Directionality(
      textDirection: strings.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: Container(
          width: min(MediaQuery.of(context).size.width * 0.92, 540),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDuplicate
                      ? colorScheme.error.withValues(alpha: 0.4)
                      : colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDuplicate
                        ? colorScheme.error.withValues(alpha: 0.15)
                        : colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with Icon and Title
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDuplicate
                              ? colorScheme.errorContainer
                              : colorScheme.primaryContainer,
                          border: Border.all(
                            color: isDuplicate
                                ? colorScheme.error.withValues(alpha: 0.3)
                                : colorScheme.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          isDuplicate
                              ? Icons.history_toggle_off_rounded
                              : Icons.report_problem_rounded,
                          color: isDuplicate
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.cairo(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDuplicate
                                    ? colorScheme.error
                                    : colorScheme.onSurface,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subtitle!,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Scrollable Body (Metadata + Unmet Conditions)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Detected Receipt Metadata Card (if any info exists)
                          if ((receiptNumber != null && receiptNumber!.isNotEmpty) ||
                              (storeChain != null && storeChain!.isNotEmpty) ||
                              (receiptDate != null && receiptDate!.isNotEmpty) ||
                              (imageUrl != null && imageUrl!.isNotEmpty) ||
                              totalValue != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.receipt_long_rounded,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        strings.dialogAuditedReceiptDetails,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (receiptNumber != null && receiptNumber!.isNotEmpty)
                                        _buildMetadataChip(
                                          context,
                                          icon: Icons.tag_rounded,
                                          label: strings.dialogReceiptNumberLabel,
                                          value: receiptNumber!,
                                        ),
                                      if (storeChain != null && storeChain!.isNotEmpty)
                                        _buildMetadataChip(
                                          context,
                                          icon: Icons.storefront_rounded,
                                          label: strings.dialogStoreChainLabel,
                                          value: branch != null && branch!.trim().isNotEmpty
                                              ? (branch!.trim().startsWith('(')
                                                  ? '$storeChain ${branch!.trim()}'
                                                  : '$storeChain (${branch!.trim()})')
                                              : storeChain!,
                                        ),
                                      if (receiptDate != null && receiptDate!.isNotEmpty)
                                        _buildMetadataChip(
                                          context,
                                          icon: Icons.calendar_today_rounded,
                                          label: strings.dialogDateLabel,
                                          value: receiptDate!,
                                        ),
                                      if (totalValue != null)
                                        _buildMetadataChip(
                                          context,
                                          icon: Icons.monetization_on_outlined,
                                          label: strings.dialogQualifyingSpendLabel,
                                          value: requiredMinimum != null
                                              ? '$totalValue $curr (${strings.isAr ? "المطلوب" : "Required"}: $requiredMinimum $curr)'
                                              : '$totalValue $curr',
                                        ),
                                      if (imageUrls != null && imageUrls!.isNotEmpty) ...[
                                        if (imageUrls!.length > 1)
                                          for (int i = 0; i < imageUrls!.length; i++)
                                            _buildImagePreviewChip(
                                              context,
                                              imageUrls![i],
                                              label: strings.isAr ? 'معاينة جزء ${i + 1}' : 'View Part ${i + 1}',
                                              allUrls: imageUrls,
                                              initialIndex: i,
                                            )
                                        else
                                          _buildImagePreviewChip(
                                            context,
                                            imageUrls!.first,
                                            allUrls: imageUrls,
                                            initialIndex: 0,
                                          ),
                                      ] else if (imageUrl != null && imageUrl!.isNotEmpty)
                                        _buildImagePreviewChip(context, imageUrl!),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          // Section Title: Unmet Conditions or Status Details
                          Row(
                            children: [
                              Icon(
                                isDuplicate ? Icons.history_toggle_off_rounded : Icons.rule_folder_rounded,
                                size: 18,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isDuplicate
                                    ? (strings.isAr ? 'بيانات وحالة الفاتورة:' : 'Receipt Status Details:')
                                    : '${strings.dialogUnmetConditionsTitle} (${conditions.length}):',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // List of Unmet Conditions (Formatted Tiles)
                          ...conditions.map((c) => _buildConditionTile(context, c)),

                          // Smart Promoter Troubleshooting Guidance (إرشادات المروج الذكية)
                          if (!isDuplicate)
                            _buildPromoterGuidanceCard(context, strings, colorScheme),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Action Button (Close / OK)
                  M3ActionButton(
                    label: strings.dialogCloseBtn,
                    icon: Icons.close_rounded,
                    variant: M3ButtonVariant.filled,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      onClose?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$label ',
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionTile(BuildContext context, ValidationConditionItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentLocale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'ar';
    final strings = AppStrings.fromLocale(currentLocale);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Container
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              size: 20,
              color: colorScheme.error,
            ),
          ),
          const SizedBox(width: 12),
          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: GoogleFonts.cairo(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDuplicate
                            ? colorScheme.secondaryContainer
                            : colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isDuplicate
                            ? '${strings.duplicateReceiptBadge} ⚠️'
                            : (strings.isAr ? 'غير مطابق ✗' : (strings.isHi ? 'शर्त अधूरी ✗' : 'Not Met ✗')),
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isDuplicate ? colorScheme.onSecondaryContainer : colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (item.value != null && item.value!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'القيمة المرصودة: ${item.value}',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviewChip(
    BuildContext context,
    String imgUrl, {
    String? label,
    List<String>? allUrls,
    int initialIndex = 0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showFullImagePreview(
        context,
        imgUrl,
        allUrls: allUrls,
        initialIndex: initialIndex,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_search_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label ?? 'معاينة صورة الفاتورة',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.zoom_in_rounded, size: 14, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  void _showFullImagePreview(
    BuildContext context,
    String imgUrl, {
    List<String>? allUrls,
    int initialIndex = 0,
  }) {
    InteractiveReceiptViewerDialog.show(
      context,
      imageUrl: imgUrl,
      imageUrls: allUrls,
      initialIndex: initialIndex,
      receiptNumber: receiptNumber,
      storeName: storeChain,
      branchName: branch,
      date: receiptDate,
      totalValue: totalValue,
      currencySymbol: currencySymbol,
    );
  }

  Widget _buildPromoterGuidanceCard(
    BuildContext context,
    AppStrings strings,
    ColorScheme colorScheme,
  ) {
    final isFooterMissing = receiptNumber == null ||
        receiptNumber!.trim().isEmpty ||
        branch == null ||
        branch!.trim().isEmpty ||
        receiptDate == null ||
        receiptDate!.trim().isEmpty;

    final isBlurry = conditions.any((c) =>
        c.description.contains('واضحة') ||
        c.description.contains('مقروء') ||
        c.description.contains('مطموس') ||
        c.description.contains('باهت'));

    final isTargetMismatch = totalValue == null ||
        totalValue! <= 0 ||
        conditions.any((c) =>
            c.description.contains('لم يتم العثور') ||
            c.description.contains('لا توجد منتجات') ||
            c.title.contains('المنتجات المؤهلة'));

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_rounded, size: 16, color: colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.isAr ? 'إرشادات المروج الذكية لتصحيح الفحص:' : 'Smart Promoter Troubleshooting Tips:',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isTargetMismatch)
            _buildGuidanceBullet(
              icon: Icons.swap_horiz_rounded,
              color: colorScheme.tertiary,
              text: strings.isAr
                  ? 'التأكد من اختيار الحملة المطابقة: تأكد من فحص الفاتورة تحت الحملة الصحيحة للشركة الراعية للعلامة التجارية عبر زر "تبديل الحملة".'
                  : 'Check Selected Campaign: Ensure the receipt is scanned under the matching brand campaign via "Switch Campaign".',
            ),
          if (isFooterMissing)
            _buildGuidanceBullet(
              icon: Icons.receipt_long_rounded,
              color: colorScheme.tertiary,
              text: strings.isAr
                  ? 'تصوير كعب الفاتورة كاملاً: تأكد من إظهار الجزء السفلي للبون الذي يحتوي على اسم الفرع، رقم الخزينة (POS)، وتاريخ الشراء والباركود.'
                  : 'Capture Full Receipt Footer: Include bottom lines showing branch, POS terminal, date, and barcode.',
            ),
          if (isBlurry)
            _buildGuidanceBullet(
              icon: Icons.camera_enhance_rounded,
              color: colorScheme.tertiary,
              text: strings.isAr
                  ? 'وضوح الصورة والإضاءة: أعد تصوير البون في إضاءة جيدة ومباشرة مع تثبيت اليد لتظهر أسطر المنتجات وأسعارها بوضوح.'
                  : 'Image Focus & Lighting: Retake photo with steady hands in clear lighting for crisp product names and prices.',
            ),
          _buildGuidanceBullet(
            icon: Icons.auto_awesome_motion_rounded,
            color: colorScheme.tertiary,
            text: strings.isAr
                ? 'الفواتير الطويلة: إذا كان البون طويلاً، يمكنك تصويره على جزأين أو أكثر (أعلى وأسفل) مع ترك سطرين متداخلين بين الصور.'
                : 'Long Receipts: You can upload up to 4 images per receipt (Top / Bottom) with 2 overlapping lines.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceBullet({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 11,
                height: 1.35,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
