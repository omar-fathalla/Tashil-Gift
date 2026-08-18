import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/animations/m3_motion.dart';
import '../../../../core/localization/app_strings.dart';

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
}) {
  final List<ValidationConditionItem> items = [];

  // 1. Minimum Spend Condition
  if (minimumSpend > 0 && targetCompanyTotal < minimumSpend) {
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
  if (!isBranchMatched || (retailChainName.isNotEmpty && storeChainDetected.isNotEmpty && !storeChainDetected.contains(retailChainName))) {
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

  // 3. Products inclusion condition
  if (!hasTargetProducts) {
    items.add(
      ValidationConditionItem(
        title: 'المنتجات المؤهلة للعرض',
        description: 'لم يتم العثور على أي منتجات تابعة لشركة "$targetCompany" داخل أصناف الفاتورة.',
        icon: Icons.remove_shopping_cart_rounded,
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

  // 5. AI detected specific conditions
  for (final cond in unfulfilledConditions) {
    final trimmed = cond.trim();
    if (trimmed.isNotEmpty && !items.any((i) => i.description.contains(trimmed) || trimmed.contains(i.title))) {
      items.add(
        ValidationConditionItem(
          title: 'شرط غير مستوفى',
          description: trimmed,
          icon: Icons.rule_folder_rounded,
          isMet: false,
        ),
      );
    }
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
                                          value: branch != null && branch!.isNotEmpty
                                              ? '$storeChain ($branch)'
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
                                      if (imageUrl != null && imageUrl!.isNotEmpty)
                                        _buildImagePreviewChip(context, imageUrl!),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          // Section Title: Unmet Conditions
                          Row(
                            children: [
                              Icon(
                                Icons.rule_folder_rounded,
                                size: 18,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${strings.dialogUnmetConditionsTitle} (${conditions.length}):',
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
                        color: colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'غير مطابق ✗',
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.error,
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

  Widget _buildImagePreviewChip(BuildContext context, String imgUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showFullImagePreview(context, imgUrl),
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
              'معاينة صورة الفاتورة',
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

  void _showFullImagePreview(BuildContext context, String imgUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('معاينة صورة الفاتورة'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: imgUrl.startsWith('data:image') || imgUrl.contains(';base64,')
                      ? Image.memory(
                          base64Decode(imgUrl.contains(',') ? imgUrl.split(',').last : imgUrl),
                          fit: BoxFit.contain,
                        )
                      : Image.network(imgUrl, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
