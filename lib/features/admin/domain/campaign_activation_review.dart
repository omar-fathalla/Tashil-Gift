import 'event_model.dart';

/// C-05: what the admin sees before a campaign is published, and the risky
/// settings worth a second look. Pure: no Firestore, no widgets.
enum ReviewLevel { danger, warning, info }

class ReviewWarning {
  final ReviewLevel level;
  final String message;
  const ReviewWarning(this.level, this.message);
}

class CampaignActivationReview {
  /// Label used for stock rows that are not tied to one branch.
  static const String generalPool = 'كل الفروع (رصيد عام)';

  final EventModel event;
  final bool isNew;
  final Map<String, List<AllocatedPrize>> stockByBranch;
  final List<ReviewWarning> warnings;

  const CampaignActivationReview._(this.event, this.isNew, this.stockByBranch, this.warnings);

  int get totalAllocated => event.allocatedPrizes.fold(0, (s, p) => s + p.allocatedQuantity);
  int get totalRemaining => event.allocatedPrizes.fold(0, (s, p) => s + p.remainingQuantity);
  bool get hasDanger => warnings.any((w) => w.level == ReviewLevel.danger);

  static String _branchOf(AllocatedPrize p) {
    final name = p.branchName.trim();
    if (name.isNotEmpty) return name;
    return p.branchId.trim().isEmpty ? generalPool : p.branchId;
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [willBeActive]: the campaign is live right after saving (a new campaign
  /// is created active; an edit keeps its current state).
  /// [pausedManually]: TAG-18, an admin turned it off from the dashboard switch,
  /// so the daily auto-activate will not turn it on.
  factory CampaignActivationReview.of(
    EventModel e, {
    required bool isNew,
    bool? willBeActive,
    bool? pausedManually,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final active = willBeActive ?? (isNew ? true : e.isActive);
    final byBranch = <String, List<AllocatedPrize>>{};
    for (final p in e.allocatedPrizes) {
      byBranch.putIfAbsent(_branchOf(p), () => []).add(p);
    }

    final w = <ReviewWarning>[];
    if (e.eventName.trim().isEmpty) {
      w.add(const ReviewWarning(ReviewLevel.danger, 'اسم الحملة فاضي.'));
    }
    if (e.companySlug.trim().isEmpty) {
      w.add(const ReviewWarning(ReviewLevel.danger, 'معرّف الشركة في الرابط فاضي؛ روابط الحملة مش هتشتغل.'));
    }

    // Dates.
    if (active && (e.startDate == null || e.endDate == null)) {
      final missing = [
        if (e.startDate == null) 'تاريخ البداية',
        if (e.endDate == null) 'آخر يوم في الحملة',
      ].join(' و');
      w.add(ReviewWarning(ReviewLevel.danger,
          'لم يتم تحديد $missing. الحملة مفعّلة، لذلك ستبقى مفتوحة بلا حد زمني وتُقبل الفواتير بأي تاريخ.'));
    }
    final todayDay = DateTime(today.year, today.month, today.day);
    if (e.endDate != null) {
      final end = DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day);
      if (end.isBefore(todayDay)) {
        w.add(ReviewWarning(ReviewLevel.danger,
            'آخر يوم في الحملة (${_day(e.endDate!)}) فات؛ الإغلاق التلقائي هيقفلها ومش هتقبل فواتير.'));
      }
    }
    if (e.startDate != null) {
      final start = DateTime(e.startDate!.year, e.startDate!.month, e.startDate!.day);
      if (start.isAfter(todayDay)) {
        w.add(ReviewWarning(ReviewLevel.info,
            'الحملة تبدأ يوم ${_day(e.startDate!)}؛ الفواتير قبل اليوم ده هتترفض.'));
      }
    }

    // Conditions.
    final hasRules = e.promotionalRules.isNotEmpty;
    if (e.minimumSpend <= 0 && e.requiredProducts.where((p) => p.trim().isNotEmpty).isEmpty && !hasRules) {
      w.add(const ReviewWarning(ReviewLevel.danger,
          'مفيش أي شرط (لا حد أدنى للشراء ولا منتجات مطلوبة ولا قواعد)؛ أي فاتورة هتبقى مؤهلة.'));
    }
    for (final r in e.promotionalRules) {
      final title = r.ruleTitle.trim().isNotEmpty ? r.ruleTitle.trim() : r.id;
      if (r.conditionType != 'by_quantity' && r.minSpend <= 0) {
        w.add(ReviewWarning(ReviewLevel.warning, 'القاعدة "$title" حدها الأدنى للشراء صفر.'));
      }
      if (r.conditionType == 'by_quantity' && r.minQuantity <= 0) {
        w.add(ReviewWarning(ReviewLevel.warning, 'القاعدة "$title" الحد الأدنى للكمية فيها صفر.'));
      }
      final scoped = r.requiredBrands.any((b) => b.trim().isNotEmpty) ||
          r.selectedBarcodes.any((b) => b.trim().isNotEmpty) ||
          r.selectedProductNames.any((b) => b.trim().isNotEmpty) ||
          r.selectedProductIds.any((b) => b.trim().isNotEmpty) ||
          r.triggerProduct.trim().isNotEmpty;
      if (!scoped) {
        w.add(ReviewWarning(ReviewLevel.warning, 'القاعدة "$title" مش مربوطة بأي منتج؛ أي صنف في الفاتورة بيتحسب.'));
      }
    }
    if (e.allowMultipleChances && e.maxChancesPerReceipt <= 0) {
      w.add(const ReviewWarning(ReviewLevel.warning,
          'تعدد الفرص مفعّل من غير حد أقصى للفرص في الفاتورة الواحدة.'));
    }

    // TAG-45 (Mohamed, 25 Nov): no stock warnings when creating or editing a
    // campaign (no stock distributed, sold-out rows, branches without stock,
    // tier gifts without a matching stock row). Stock is managed on its own
    // screens and the server still decides every claim.

    // Behaviour worth knowing about.
    if (e.customPrompt.trim().isEmpty) {
      w.add(const ReviewWarning(ReviewLevel.warning, 'تعليمات قراءة الفواتير بالذكاء الاصطناعي فاضية.'));
    }
    if (e.enableWhatsAppWinnerNotification) {
      w.add(const ReviewWarning(ReviewLevel.info, 'هيتبعت للفائزين رسالة واتساب تلقائيًا.'));
    }
    if (e.allowComplementaryReceipts) {
      w.add(const ReviewWarning(ReviewLevel.info, 'الفواتير التكميلية مسموحة (أكتر من فاتورة لنفس العميل).'));
    }
    // TAG-18: an off campaign whose dates cover today or later.
    if (!active && e.endDate != null) {
      final end = DateTime(e.endDate!.year, e.endDate!.month, e.endDate!.day);
      if (!end.isBefore(todayDay)) {
        if (pausedManually ?? e.pausedManually) {
          w.add(const ReviewWarning(ReviewLevel.warning,
              'الحملة متوقفة يدويًا، فمش هتتفعّل تلقائيًا في مواعيدها. لو عايزها تشتغل، فعّلها من مفتاح الحالة في لوحة التحكم.'));
        } else if (e.startDate != null) {
          final start = DateTime(e.startDate!.year, e.startDate!.month, e.startDate!.day);
          final tomorrow = todayDay.add(const Duration(days: 1));
          final on = start.isAfter(todayDay) ? start : tomorrow;
          w.add(ReviewWarning(ReviewLevel.info,
              'الحملة متوقفة دلوقتي، وهتتفعّل تلقائيًا يوم ${_day(on)} الساعة 12:10 بعد نص الليل. لو عايزها تشتغل قبل كده، فعّلها من مفتاح الحالة في لوحة التحكم.'));
        }
      }
    }
    if (active) {
      w.add(ReviewWarning(ReviewLevel.info,
          isNew ? 'الحملة هتتفعّل وتظهر للمندوبين والفروع فورًا.' : 'الحملة مفعّلة؛ التعديل هيوصل للمندوبين والفروع فورًا.'));
    }

    w.sort((a, b) => a.level.index.compareTo(b.level.index));
    return CampaignActivationReview._(e, isNew, byBranch, w);
  }

  /// Arabic name of the prize game (the stored value is an internal code).
  static String gameLabel(String gameType) => switch (gameType) {
        'wheel' => 'عجلة الحظ',
        'scratch' => 'امسح واربح',
        'directGift' => 'هدية فورية مباشرة',
        'chooseGift' => 'اختر هديتك',
        _ => 'حسب إعداد الحملة',
      };

  /// One line per rule, for the summary.
  static String describeRule(PromotionalRuleItem r) {
    final title = r.ruleTitle.trim().isNotEmpty ? r.ruleTitle.trim() : r.id;
    final scope = [
      ...r.requiredBrands.where((b) => b.trim().isNotEmpty),
      ...r.selectedProductNames.where((b) => b.trim().isNotEmpty),
    ];
    final cond = r.conditionType == 'by_quantity'
        ? 'كمية ${r.minQuantity} على الأقل'
        : 'شراء بـ ${_num(r.minSpend)} على الأقل${r.maxSpend != null ? ' وحتى ${_num(r.maxSpend!)}' : ''}';
    final products = scope.isEmpty
        ? (r.selectedBarcodes.isNotEmpty ? ' (${r.selectedBarcodes.length} باركود)' : '')
        : ' من: ${scope.take(4).join('، ')}${scope.length > 4 ? '…' : ''}';
    return '$title: $cond$products';
  }
}
