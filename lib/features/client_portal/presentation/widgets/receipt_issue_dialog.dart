import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Every reason a receipt can fail for the rep, with a short bilingual
/// headline + "what to do" hint. Used for AI condition mismatches, duplicates
/// and technical errors so the rep never sees raw technical text.
enum ReceiptIssueKind {
  noImage,
  campaignUnavailable,
  campaignEnded,
  campaignNotStarted,
  notReceipt,
  unreadable,
  incomplete,
  handwritten,
  tampered,
  screenCapture,
  wrongChain,
  wrongBranch,
  outOfDate,
  noProducts,
  belowMinimum,
  promoNotMet,
  multiNoMatch,
  alreadyRedeemed,
  permission,
  timeout,
  network,
  aiUnavailable,
  aiBilling,
  rateLimit,
  appCheck,
  generic,
}

enum ReceiptIssueAction { retake, tryAgain, close }

class ReceiptIssueSpec {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final String hintAr;
  final String hintEn;
  final ReceiptIssueAction action;
  const ReceiptIssueSpec(this.icon, this.titleAr, this.titleEn, this.hintAr, this.hintEn, this.action);
}

const Map<ReceiptIssueKind, ReceiptIssueSpec> receiptIssueSpecs = {
  ReceiptIssueKind.noImage: ReceiptIssueSpec(Icons.add_a_photo_rounded, 'أضف صورة الفاتورة أولاً', 'Add a receipt photo first',
      'صوّر الفاتورة أو اخترها من المعرض ثم اضغط فحص.', 'Take or pick a receipt photo, then tap Scan.', ReceiptIssueAction.close),
  ReceiptIssueKind.campaignUnavailable: ReceiptIssueSpec(Icons.event_busy_rounded, 'الحملة غير متاحة', 'Campaign unavailable',
      'افتح رابط الحملة من جديد أو تواصل مع المشرف.', 'Reopen the campaign link or contact your supervisor.', ReceiptIssueAction.close),
  ReceiptIssueKind.campaignEnded: ReceiptIssueSpec(Icons.event_busy_rounded, 'انتهت الحملة', 'Campaign has ended',
      'لا يمكن قبول فواتير جديدة لهذه الحملة.', 'New receipts can no longer be accepted.', ReceiptIssueAction.close),
  ReceiptIssueKind.campaignNotStarted: ReceiptIssueSpec(Icons.schedule_rounded, 'الحملة لم تبدأ بعد', 'Campaign not started yet',
      'أعد المحاولة عند بدء الحملة.', 'Try again once the campaign starts.', ReceiptIssueAction.close),
  ReceiptIssueKind.notReceipt: ReceiptIssueSpec(Icons.receipt_long_rounded, 'الصورة ليست بون كاشير', 'Not a cashier receipt',
      'صوّر بون الكاشير المطبوع من الماكينة.', 'Photograph the printed cashier (POS) receipt.', ReceiptIssueAction.retake),
  ReceiptIssueKind.unreadable: ReceiptIssueSpec(Icons.blur_on_rounded, 'الصورة غير واضحة', 'Photo is not clear',
      'صوّر مرة أخرى في إضاءة جيدة وبدون اهتزاز.', 'Retake in good light and hold the phone steady.', ReceiptIssueAction.retake),
  ReceiptIssueKind.incomplete: ReceiptIssueSpec(Icons.crop_free_rounded, 'الفاتورة غير كاملة في الصورة', 'Receipt is cut off',
      'اظهر الفاتورة كاملة من الأعلى للأسفل (أو صوّرها على جزأين).', 'Show the whole receipt top to bottom (or shoot it in two parts).', ReceiptIssueAction.retake),
  ReceiptIssueKind.handwritten: ReceiptIssueSpec(Icons.edit_note_rounded, 'فاتورة مكتوبة بخط اليد', 'Handwritten receipt',
      'المقبول فقط بون الكاشير المطبوع.', 'Only printed cashier receipts are accepted.', ReceiptIssueAction.retake),
  ReceiptIssueKind.tampered: ReceiptIssueSpec(Icons.gpp_maybe_rounded, 'يوجد تعديل أو شطب في الفاتورة', 'Receipt looks edited',
      'استخدم الفاتورة الأصلية بدون أي تعديل.', 'Use the original receipt without any edits.', ReceiptIssueAction.retake),
  ReceiptIssueKind.screenCapture: ReceiptIssueSpec(Icons.phone_android_rounded, 'الصورة ملتقطة من شاشة', 'Photo taken of a screen',
      'صوّر الفاتورة الورقية الأصلية مباشرة.', 'Photograph the original paper receipt.', ReceiptIssueAction.retake),
  ReceiptIssueKind.wrongChain: ReceiptIssueSpec(Icons.storefront_rounded, 'الفاتورة من سلسلة غير مشاركة', 'Store chain not in this offer',
      'العرض صالح فقط في السلاسل المحددة بالحملة.', 'The offer is valid only at the campaign\'s store chains.', ReceiptIssueAction.close),
  ReceiptIssueKind.wrongBranch: ReceiptIssueSpec(Icons.location_off_rounded, 'الفرع غير مشارك في العرض', 'Branch not in this offer',
      'تأكد أن الفاتورة من أحد الفروع المعتمدة.', 'Make sure the receipt is from an approved branch.', ReceiptIssueAction.close),
  ReceiptIssueKind.outOfDate: ReceiptIssueSpec(Icons.event_rounded, 'تاريخ الفاتورة خارج فترة العرض', 'Receipt date is outside the offer',
      'المقبول فقط الفواتير خلال فترة الحملة.', 'Only receipts dated within the campaign are accepted.', ReceiptIssueAction.close),
  ReceiptIssueKind.noProducts: ReceiptIssueSpec(Icons.remove_shopping_cart_rounded, 'لا توجد منتجات العرض في الفاتورة', 'No offer products on the receipt',
      'تأكد أن الفاتورة تحتوي منتجات الشركة المشاركة.', 'Check the receipt contains the brand\'s products.', ReceiptIssueAction.retake),
  ReceiptIssueKind.belowMinimum: ReceiptIssueSpec(Icons.price_check_rounded, 'قيمة المشتريات أقل من المطلوب', 'Purchase is below the minimum',
      'يحتاج العميل لإضافة منتجات حتى يصل للحد الأدنى.', 'The customer needs to buy more to reach the minimum.', ReceiptIssueAction.close),
  ReceiptIssueKind.promoNotMet: ReceiptIssueSpec(Icons.inventory_2_outlined, 'شروط العرض غير مكتملة', 'Offer conditions not met',
      'راجع الأصناف والكميات المطلوبة للعرض.', 'Check the required items and quantities.', ReceiptIssueAction.close),
  ReceiptIssueKind.multiNoMatch: ReceiptIssueSpec(Icons.layers_clear_rounded, 'الفاتورة لا تطابق أي عرض', 'Receipt matches no offer',
      'راجع شروط عروض الشركة.', 'Review the company\'s offer conditions.', ReceiptIssueAction.close),
  ReceiptIssueKind.alreadyRedeemed: ReceiptIssueSpec(Icons.verified_rounded, 'الفاتورة دي اترفعت واتقبلت قبل كده', 'Receipt already uploaded and accepted',
      'لا يمكن استخدام نفس الفاتورة مرتين. استخدم فاتورة جديدة.', 'A receipt can be used only once. Use a new receipt.', ReceiptIssueAction.close),
  ReceiptIssueKind.permission: ReceiptIssueSpec(Icons.lock_outline_rounded, 'تعذّر حفظ الفاتورة', 'Could not save the receipt',
      'أعد فتح رابط الحملة ثم حاول مرة أخرى.', 'Reopen the campaign link and try again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.timeout: ReceiptIssueSpec(Icons.hourglass_bottom_rounded, 'الفحص اتأخر، دوس حاول مرة أخرى', 'The scan took too long',
      'دوس "حاول مرة أخرى" لإعادة الفحص.', 'Tap "Try again" to scan again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.network: ReceiptIssueSpec(Icons.wifi_off_rounded, 'لا يوجد اتصال بالإنترنت', 'No internet connection',
      'تأكد من الإنترنت ثم حاول مرة أخرى.', 'Check your connection and try again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.aiUnavailable: ReceiptIssueSpec(Icons.cloud_off_rounded, 'خدمة الفحص غير متاحة الآن', 'Scanning service is unavailable',
      'انتظر دقيقة ثم حاول مرة أخرى.', 'Wait a minute and try again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.aiBilling: ReceiptIssueSpec(Icons.cloud_off_rounded, 'خدمة الفحص متوقفة مؤقتاً', 'Scanning is paused',
      'تواصل مع المشرف لإعادة تفعيل الخدمة.', 'Contact your supervisor to restore the service.', ReceiptIssueAction.close),
  ReceiptIssueKind.rateLimit: ReceiptIssueSpec(Icons.hourglass_top_rounded, 'محاولات كثيرة في وقت قصير', 'Too many attempts',
      'انتظر دقيقة ثم حاول مرة أخرى.', 'Wait a minute, then try again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.appCheck: ReceiptIssueSpec(Icons.shield_outlined, 'تعذّر التحقق من الجهاز', 'Device check failed',
      'حدّث الصفحة ثم حاول مرة أخرى.', 'Refresh the page and try again.', ReceiptIssueAction.tryAgain),
  ReceiptIssueKind.generic: ReceiptIssueSpec(Icons.error_outline_rounded, 'حدث خطأ غير متوقع', 'Something went wrong',
      'حاول مرة أخرى، وإن تكرر تواصل مع المشرف.', 'Try again; if it repeats, contact your supervisor.', ReceiptIssueAction.tryAgain),
};

/// Maps any exception (Firebase, network, AI) to a rep-friendly kind.
ReceiptIssueKind classifyReceiptException(Object error) {
  final s = error.toString().toLowerCase();
  bool has(List<String> k) => k.any(s.contains);
  if (has(['app-check', 'app check', 'appcheck', 'app_check'])) return ReceiptIssueKind.appCheck;
  if (has(['resource-exhausted', 'resource_exhausted', 'rate limit', '429', 'too many'])) return ReceiptIssueKind.rateLimit;
  if (has(['billing', 'prepayment', 'credits are depleted', 'quota'])) return ReceiptIssueKind.aiBilling;
  // 2.0.151+212: a timeout is not a network failure; it gets its own message.
  if (error is TimeoutException || has(['timeoutexception', 'deadline-exceeded', 'deadline_exceeded', 'timeout', 'timed out'])) {
    return ReceiptIssueKind.timeout;
  }
  if (has(['network', 'failed to fetch', 'xmlhttprequest', 'socket', 'connection', 'offline', 'unavailable'])) {
    return s.contains('unavailable') && !has(['network', 'fetch', 'offline', 'connection']) ? ReceiptIssueKind.aiUnavailable : ReceiptIssueKind.network;
  }
  if (has(['permission-denied', 'permission_denied', 'insufficient permissions', 'unauthenticated'])) return ReceiptIssueKind.permission;
  if (has(['ai_service_error', 'geminigenerate', 'gemini', 'generative', 'internal', 'firebase_functions', '500', '503'])) return ReceiptIssueKind.aiUnavailable;
  return ReceiptIssueKind.generic;
}

/// Maps a free-text AI/rule condition (Arabic or English) to a kind.
ReceiptIssueKind classifyConditionText(String text) {
  final s = text.toLowerCase();
  bool has(List<String> k) => k.any(s.contains);
  if (has(['خط اليد', 'يدوي', 'handwritten'])) return ReceiptIssueKind.handwritten;
  if (has(['شطب', 'تلاعب', 'tamper'])) return ReceiptIssueKind.tampered;
  if (has(['شاشة', 'screen'])) return ReceiptIssueKind.screenCapture;
  if (has(['ليس بون', 'ليست فاتورة', 'غير معتمد', 'not a receipt'])) return ReceiptIssueKind.notReceipt;
  if (has(['غير واضح', 'مطموس', 'مقروء', 'باهت', 'blurry', 'unreadable'])) return ReceiptIssueKind.unreadable;
  if (has(['غير كامل', 'مقطوع', 'ناقص', 'كعب', 'incomplete'])) return ReceiptIssueKind.incomplete;
  if (has(['تاريخ', 'فترة', 'date'])) return ReceiptIssueKind.outOfDate;
  if (has(['فرع', 'branch'])) return ReceiptIssueKind.wrongBranch;
  if (has(['سلسلة', 'متجر', 'chain', 'store'])) return ReceiptIssueKind.wrongChain;
  if (has(['الحد الأدنى', 'حد أدنى', 'أقل من', 'minimum', 'إنفاق'])) return ReceiptIssueKind.belowMinimum;
  if (has(['منتجات', 'أصناف', 'products'])) return ReceiptIssueKind.noProducts;
  return ReceiptIssueKind.promoNotMet;
}

class ReceiptCheckChip {
  final String labelAr;
  final String labelEn;
  final bool met;
  final String? value;
  const ReceiptCheckChip(this.labelAr, this.labelEn, this.met, {this.value});
}

class ReceiptIssueDetail {
  final IconData icon;
  final String labelAr;
  final String labelEn;
  final String value;
  const ReceiptIssueDetail(this.icon, this.labelAr, this.labelEn, this.value);
}

/// Shows the unified issue dialog. [onPrimary] runs after the dialog closes
/// (e.g. clear photos to retake, or retry the scan).
Future<void> showReceiptIssueDialog({
  required BuildContext context,
  required ReceiptIssueKind kind,
  required bool isArabic,
  List<ReceiptCheckChip> chips = const [],
  List<ReceiptIssueDetail> details = const [],
  List<String> extraReasons = const [],
  String? subtitleOverride,
  String? errorCode,
  VoidCallback? onPrimary,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ReceiptIssueDialog(
      kind: kind,
      isArabic: isArabic,
      chips: chips,
      details: details,
      extraReasons: extraReasons,
      subtitleOverride: subtitleOverride,
      errorCode: errorCode,
      onPrimary: onPrimary,
    ),
  );
}

class ReceiptIssueDialog extends StatelessWidget {
  final ReceiptIssueKind kind;
  final bool isArabic;
  final List<ReceiptCheckChip> chips;
  final List<ReceiptIssueDetail> details;
  final List<String> extraReasons;
  final String? subtitleOverride;
  /// 2.0.148: raw error code shown small under the hint (for support).
  final String? errorCode;
  final VoidCallback? onPrimary;

  const ReceiptIssueDialog({
    super.key,
    required this.kind,
    required this.isArabic,
    this.chips = const [],
    this.details = const [],
    this.extraReasons = const [],
    this.subtitleOverride,
    this.errorCode,
    this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = receiptIssueSpecs[kind]!;
    final ar = isArabic;
    final isDup = kind == ReceiptIssueKind.alreadyRedeemed;
    final accent = isDup ? cs.tertiary : cs.error;
    final accentBg = isDup ? cs.tertiaryContainer : cs.errorContainer;
    final font = GoogleFonts.cairo;
    final actionLabel = switch (spec.action) {
      ReceiptIssueAction.retake => ar ? 'إعادة التصوير' : 'Retake photo',
      ReceiptIssueAction.tryAgain => ar ? 'حاول مرة أخرى' : 'Try again',
      ReceiptIssueAction.close => ar ? 'فهمت' : 'Got it',
    };
    final actionIcon = switch (spec.action) {
      ReceiptIssueAction.retake => Icons.photo_camera_rounded,
      ReceiptIssueAction.tryAgain => Icons.refresh_rounded,
      ReceiptIssueAction.close => Icons.check_rounded,
    };

    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: accentBg, shape: BoxShape.circle),
                    child: Icon(spec.icon, size: 36, color: accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  ar ? spec.titleAr : spec.titleEn,
                  textAlign: TextAlign.center,
                  style: font(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.3),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 20, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          subtitleOverride ?? (ar ? spec.hintAr : spec.hintEn),
                          style: font(fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (errorCode != null && errorCode!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${ar ? 'رمز الخطأ' : 'Error code'}: ${errorCode!.trim()}',
                    key: const Key('receipt_issue_error_code'),
                    textAlign: TextAlign.center,
                    style: font(fontSize: 11, color: cs.outline),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < details.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(details[i].icon, size: 18, color: cs.primary),
                                const SizedBox(width: 10),
                                Text(ar ? details[i].labelAr : details[i].labelEn,
                                    style: font(fontSize: 13, color: cs.onSurfaceVariant)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    details[i].value,
                                    textAlign: TextAlign.end,
                                    style: font(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final c in chips)
                        Chip(
                          avatar: Icon(c.met ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 18, color: c.met ? cs.primary : cs.error),
                          label: Text(
                            c.value == null ? (ar ? c.labelAr : c.labelEn) : '${ar ? c.labelAr : c.labelEn}: ${c.value}',
                            style: font(fontSize: 12.5, fontWeight: FontWeight.w600,
                                color: c.met ? cs.onSecondaryContainer : cs.onErrorContainer),
                          ),
                          backgroundColor: c.met ? cs.secondaryContainer : cs.errorContainer,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                if (extraReasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      title: Text(ar ? 'التفاصيل' : 'Details',
                          style: font(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                      children: [
                        for (final r in extraReasons.take(5))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('•  ', style: font(color: cs.onSurfaceVariant)),
                                Expanded(child: Text(r, style: font(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.5))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (spec.action != ReceiptIssueAction.close) onPrimary?.call();
                  },
                  icon: Icon(actionIcon),
                  label: Text(actionLabel, style: font(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (spec.action != ReceiptIssueAction.close) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(ar ? 'إغلاق' : 'Close', style: font(fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
