import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';

/// Screen displayed when an event uses the "Choose Your Gift" (اختر هديتك - شبكة الاختيارات) game type.
/// The customer freely picks and confirms their favorite reward from an interactive grid of available gifts.
class ChooseGiftScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String eventId;
  final String? companySlug;
  final List<String> prizes;
  final int totalChances;
  final bool isDemo;
  final String? branchId;
  final Map<String, String>? prizeImages;

  const ChooseGiftScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    this.companySlug,
    this.prizes = const [],
    this.totalChances = 1,
    this.isDemo = false,
    this.branchId,
    this.prizeImages,
  });

  @override
  ConsumerState<ChooseGiftScreen> createState() => _ChooseGiftScreenState();
}

class _ChooseGiftScreenState extends ConsumerState<ChooseGiftScreen>
    with TickerProviderStateMixin {
  late final List<String> _items;
  int? _selectedGiftIndex;
  bool _isConfirming = false;
  late int _remainingChances;
  int _currentRound = 1;
  final List<String> _wonPrizes = [];
  Map<String, String> _prizeImages = {};

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.prizeImages != null && widget.prizeImages!.isNotEmpty) {
      _prizeImages = Map.from(widget.prizeImages!);
    }
    _loadEventPrizeImages();
    _remainingChances = widget.totalChances > 0 ? widget.totalChances : 1;
    final rawPrizes = widget.prizes.isNotEmpty
        ? widget.prizes
        : [
            'ساعة ذكية فاخرة ⌚',
            'قسيمة مشتريات 150 ج.م 🎟️',
            'سماعات لاسلكية Pro 🎧',
            'ماكينة قهوة اسبريسو ☕',
            'خلاط كهربائي سريع ⚡',
            'طقم أواني فاخر 🍳',
          ];
    final seen = <String>{};
    _items = rawPrizes.where((p) => p.trim().isNotEmpty && seen.add(p.trim())).toList();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadEventPrizeImages() async {
    try {
      final giftsService = ref.read(companyGiftsServiceProvider);
      final resolved = await giftsService.resolvePrizeImagesForEvent(
        eventId: widget.eventId,
        companySlug: widget.companySlug,
      );
      if (resolved.isNotEmpty && mounted) {
        setState(() {
          _prizeImages.addAll(resolved);
        });
      }
    } catch (_) {}
  }

  String? _resolvePrizeImage(String prizeName) {
    if (_prizeImages.containsKey(prizeName)) {
      final img = _prizeImages[prizeName];
      if (img != null && img.trim().isNotEmpty) return img.trim();
    }
    // Clean and phonetically normalized comparison
    final cleanName = _normalizeGiftName(prizeName);
    for (final entry in _prizeImages.entries) {
      final k = _normalizeGiftName(entry.key);
      if (k.isNotEmpty && (k == cleanName || cleanName.contains(k) || k.contains(cleanName))) {
        if (entry.value.trim().isNotEmpty) return entry.value.trim();
      }
    }
    return null;
  }

  String _normalizeGiftName(String name) {
    return name
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\s\-_\.]+'), ' ')
        .trim()
        .toLowerCase();
  }

  IconData _getPrizeIcon(String prizeName) {
    final lower = prizeName.toLowerCase();
    if (lower.contains('فواتشر') || lower.contains('قسيمة') || lower.contains('voucher') || lower.contains('coupon')) {
      return Icons.confirmation_number_rounded;
    }
    if (lower.contains('ساعة') || lower.contains('watch')) {
      return Icons.watch_rounded;
    }
    if (lower.contains('سماعة') || lower.contains('headphone') || lower.contains('audio')) {
      return Icons.headphones_rounded;
    }
    if (lower.contains('قهوة') || lower.contains('شاي') || lower.contains('coffee')) {
      return Icons.coffee_rounded;
    }
    if (lower.contains('شاشة') || lower.contains('tv') || lower.contains('تلفزيون')) {
      return Icons.tv_rounded;
    }
    if (lower.contains('شامبو') || lower.contains('بلسم') || lower.contains('كريم') || lower.contains('عناية')) {
      return Icons.spa_rounded;
    }
    if (lower.contains('اسبراي') || lower.contains('رول') || lower.contains('مزيل')) {
      return Icons.sanitizer_rounded;
    }
    return Icons.card_giftcard_rounded;
  }

  Color _getPrizeAccentColor(BuildContext context, int index) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
      Colors.teal,
      Colors.indigo,
      Colors.deepPurple,
      Colors.amber.shade800,
      Colors.pink.shade600,
      Colors.blue.shade700,
    ];
    return colors[index % colors.length];
  }

  Future<void> _handleConfirmSelection() async {
    if (_selectedGiftIndex == null || _isConfirming) return;

    final selectedPrize = _items[_selectedGiftIndex!];
    final audioService = ref.read(gameAudioServiceProvider);

    setState(() {
      _isConfirming = true;
    });

    try {
      audioService.playWinFanfare();

      _remainingChances = (_remainingChances - 1).clamp(0, 999);
      _wonPrizes.add(selectedPrize);

      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'chooseGift',
          'prize_won': _wonPrizes.join(' + '),
          'prizes_won': _wonPrizes,
          'remaining_chances': _remainingChances,
          'event_id': widget.eventId,
          'claimed_gifts': _wonPrizes.map((p) => {
            'giftId': '',
            'giftName': p,
            'quantity': 1,
            'unitValue': 0.0,
            'isVoucher': p.contains('فواتشر') || p.contains('قسيمة') || p.toLowerCase().contains('voucher'),
          }).toList(),
        });

        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          await giftsService.decrementCampaignPrize(
            widget.eventId,
            selectedPrize,
            branchId: widget.branchId,
          );
        }
      }

      if (!mounted) return;

      final imgUrl = _resolvePrizeImage(selectedPrize);

      final isAr = ref.read(localeProvider).languageCode == 'ar';
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: selectedPrize,
        remainingChances: _remainingChances,
        nextChanceLabel: isAr
            ? 'اختيار الهدية التالية (متبقي $_remainingChances) 🎁'
            : 'Choose Next Gift ($_remainingChances left) 🎁',
        imageUrl: imgUrl,
        onNextChance: () {
          if (!mounted) return;
          setState(() {
            _selectedGiftIndex = null;
            _isConfirming = false;
            _currentRound++;
          });
        },
        onNextCustomer: () {
          Navigator.of(context).pop();
        },
      );

      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسجيل الهدية')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      setState(() {
        _isConfirming = false;
      });
    }
  }

  Future<void> _handleBackNavigation() async {
    if (_isConfirming) return;

    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final totalChances = widget.totalChances > 0 ? widget.totalChances : 1;

    if (_wonPrizes.isEmpty) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_rounded, color: Colors.amber.shade800, size: 30),
            ),
            title: Text(
              isAr ? 'العودة لشاشة رفع الفواتير' : 'Return to Upload Receipts',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            content: Text(
              isAr
                  ? 'هل أنت متأكد من العودة دون اختيار أي هدية؟\n\nلن يتم تسجيل صرف أي هدية لهذه الفاتورة، ولن تُحتسب في المخزون، ويمكنك إعادة فحصها أو رفعها لاحقاً.'
                  : 'Are you sure you want to return without choosing any gift?\n\nNo gift will be recorded or deducted for this receipt, and you can re-scan it later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 13.5, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(
                  isAr ? 'البقاء واختيار هدية' : 'Stay & Pick Gift',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                label: Text(
                  isAr ? 'نعم، إلغاء والعودة' : 'Yes, Cancel & Return',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );

      if (shouldLeave != true) return;

      // Clean up uncompleted pending transaction if not demo
      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        try {
          final firestore = ref.read(firestoreProvider);
          await firestore.collection('receipts_transactions').doc(widget.transactionId).delete();
        } catch (e) {
          debugPrint('Error cleaning up uncompleted transaction doc: $e');
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded, color: Colors.blue.shade700, size: 30),
            ),
            title: Text(
              isAr ? 'إنهاء الاختيار والعودة' : 'Finish & Exit',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            content: Text(
              isAr
                  ? 'لقد قمت باختيار (${_wonPrizes.length}) من إجمالي ($totalChances) هدايا.\n\nهل تريد إنهاء الجلسة والعودة بالهدايا التي تم اختيارها بالفعل؟'
                  : 'You have chosen (${_wonPrizes.length}) of ($totalChances) gifts.\n\nDo you want to finish and exit with the chosen gifts?',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 13.5, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(
                  isAr ? 'متابعة بقية الهدايا' : 'Continue Picking',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(
                  isAr ? 'نعم، اكتفيت بالهدايا' : 'Yes, Exit Now',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );

      if (shouldLeave == true && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _resetDemo() {
    setState(() {
      _selectedGiftIndex = null;
      _isConfirming = false;
      _remainingChances = widget.totalChances > 0 ? widget.totalChances : 2;
      _currentRound = 1;
      _wonPrizes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final audioService = ref.watch(gameAudioServiceProvider);

    final totalChances = widget.totalChances > 0 ? widget.totalChances : 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleBackNavigation();
        },
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            leading: BackButton(
              onPressed: _handleBackNavigation,
            ),
            title: Text(
              isAr
                  ? 'اختر هديتك ($totalChances ${totalChances == 1 ? 'هدية مستحقة' : 'هدايا مستحقة'})'
                  : 'Choose Your Gift ($totalChances ${totalChances == 1 ? 'Gift' : 'Gifts'})',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: isMobile ? 16 : 18),
            ),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              TextButton.icon(
                onPressed: _handleBackNavigation,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  isAr ? 'إلغاء والعودة' : 'Cancel',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const SizedBox(width: 4),
              const GameSoundToggleButton(),
              const SizedBox(width: 8),
            ],
          ),
        bottomNavigationBar: _selectedGiftIndex != null
            ? Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 10 : 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totalChances > 1
                                  ? (isAr
                                      ? 'الهدية المختارة للفرصة ($_currentRound من إجمالي $totalChances):'
                                      : 'Selected for Chance ($_currentRound of $totalChances):')
                                  : (isAr ? 'الهدية المختارة حالياً:' : 'Currently Selected Gift:'),
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _items[_selectedGiftIndex!],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: isMobile ? 10 : 16),
                      FilledButton.icon(
                        icon: _isConfirming
                            ? SizedBox(
                                width: isMobile ? 16 : 20,
                                height: isMobile ? 16 : 20,
                                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(Icons.check_circle_rounded, size: isMobile ? 18 : 20),
                        label: Text(
                          _isConfirming
                              ? (isAr ? 'جاري التأكيد...' : 'Confirming...')
                              : (totalChances > 1
                                  ? (_remainingChances > 1
                                      ? (isAr
                                          ? 'تأكيد الهدية ($_currentRound من $totalChances) ➔'
                                          : 'Confirm Gift ($_currentRound of $totalChances) ➔')
                                      : (isAr
                                          ? 'تأكيد الهدية الأخيرة ($_currentRound من $totalChances) 🎁'
                                          : 'Confirm Final Gift ($_currentRound of $totalChances) 🎁'))
                                  : (isAr ? 'تأكيد الهدية 🎁' : 'Confirm Gift 🎁')),
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: isMobile ? 12.5 : 14.5),
                        ),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 10 : 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isConfirming ? null : _handleConfirmSelection,
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (widget.isDemo)
                GameDemoBanner(
                  onReset: _resetDemo,
                ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 12.0 : 20.0,
                    isMobile ? 8.0 : 12.0,
                    isMobile ? 12.0 : 20.0,
                    isMobile ? 90.0 : 32.0,
                  ),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        children: [
                          // Status & Qualified Wins Indicator Banner
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 14 : 20,
                              vertical: isMobile ? 12 : 16,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primaryContainer.withValues(alpha: 0.85),
                                  colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                ],
                                begin: AlignmentDirectional.topStart,
                                end: AlignmentDirectional.bottomEnd,
                              ),
                              borderRadius: BorderRadius.circular(isMobile ? 16 : 22),
                              border: Border.all(
                                color: totalChances > 1 ? const Color(0xFFFFB300) : colorScheme.primary.withValues(alpha: 0.3),
                                width: totalChances > 1 ? 2.0 : 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (totalChances > 1 ? const Color(0xFFFFB300) : colorScheme.primary).withValues(alpha: 0.12),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Top Badges Row: Total Qualified Wins & Remaining Counter
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 10 : 14,
                                        vertical: isMobile ? 5 : 7,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: totalChances > 1
                                              ? [const Color(0xFFFF8F00), const Color(0xFFFFA000)]
                                              : [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.85)],
                                        ),
                                        borderRadius: BorderRadius.circular(30),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (totalChances > 1 ? const Color(0xFFFF8F00) : colorScheme.primary).withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            totalChances > 1 ? Icons.emoji_events_rounded : Icons.card_giftcard_rounded,
                                            color: Colors.white,
                                            size: isMobile ? 16 : 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isAr
                                                ? 'عدد مرات الفوز: ${totalChances == 1 ? 'مرة واحدة (هدية واحدة)' : totalChances == 2 ? 'مرتان (هديتان)' : '$totalChances مرات ($totalChances هدايا)'}'
                                                : 'Total Wins: $totalChances ${totalChances == 1 ? 'Gift' : 'Gifts'}',
                                            style: GoogleFonts.cairo(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: isMobile ? 11.5 : 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (totalChances > 1) ...[
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isMobile ? 8 : 12,
                                              vertical: isMobile ? 4 : 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.92),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: colorScheme.primary.withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.hourglass_top_rounded,
                                                  size: isMobile ? 13 : 15,
                                                  color: colorScheme.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isAr ? '$_remainingChances متبقية' : '$_remainingChances left',
                                                  style: GoogleFonts.cairo(
                                                    color: colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: isMobile ? 10.5 : 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        // Direct Back / Return Quick Action Chip
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _handleBackNavigation,
                                            borderRadius: BorderRadius.circular(20),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: isMobile ? 8 : 12,
                                                vertical: isMobile ? 4 : 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50.withValues(alpha: 0.95),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: Colors.red.shade200,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.exit_to_app_rounded,
                                                    size: isMobile ? 13 : 15,
                                                    color: Colors.red.shade700,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    isAr ? 'عودة للفواتير' : 'Back to Receipts',
                                                    style: GoogleFonts.cairo(
                                                      color: Colors.red.shade700,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: isMobile ? 10.5 : 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                SizedBox(height: isMobile ? 10 : 12),

                                // 2. Instructions & Current Round Explanation
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(isMobile ? 8 : 10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.touch_app_rounded, color: Colors.white, size: isMobile ? 18 : 22),
                                    ),
                                    SizedBox(width: isMobile ? 10 : 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            totalChances > 1
                                                ? (isAr
                                                    ? 'الفرصة الحالية: اختيار الهدية رقم ($_currentRound) من إجمالي ($totalChances) هدايا'
                                                    : 'Current Round: Choosing gift #$_currentRound of $totalChances')
                                                : (isAr
                                                    ? 'انقر على هديتك المفضلة للاختيار'
                                                    : strings.chooseYourGiftPrompt),
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w900,
                                              fontSize: isMobile ? 13.5 : 15.5,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            totalChances > 1
                                                ? (isAr
                                                    ? 'اختر هديتك للفرصة ($_currentRound) واضغط تأكيد الهدية للانتقال للفرصة التالية'
                                                    : 'Pick your reward for chance #$_currentRound and confirm')
                                                : (isAr
                                                    ? 'اختر الهدية التي تفضلها واضغط تأكيد الهدية'
                                                    : 'Tap your preferred reward and confirm'),
                                            style: GoogleFonts.cairo(
                                              fontSize: isMobile ? 11 : 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // 3. Multi-chance Step Indicators
                                if (totalChances > 1) ...[
                                  SizedBox(height: isMobile ? 12 : 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: List.generate(totalChances, (i) {
                                      final roundNum = i + 1;
                                      final isCompleted = roundNum < _currentRound;
                                      final isCurrent = roundNum == _currentRound;
                                      final wonGift = isCompleted && i < _wonPrizes.length ? _wonPrizes[i] : null;

                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isMobile ? 8 : 12,
                                          vertical: isMobile ? 4 : 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? colorScheme.primary
                                              : isCompleted
                                                  ? Colors.green.shade600
                                                  : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isCurrent
                                                ? colorScheme.primary
                                                : isCompleted
                                                    ? Colors.green.shade700
                                                    : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isCompleted
                                                  ? Icons.check_circle_rounded
                                                  : isCurrent
                                                      ? Icons.radio_button_checked_rounded
                                                      : Icons.radio_button_unchecked_rounded,
                                              size: isMobile ? 13 : 15,
                                              color: isCompleted || isCurrent ? Colors.white : Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              isCompleted
                                                  ? (wonGift != null
                                                      ? (isAr ? 'الهدية $roundNum: $wonGift ✓' : 'Gift $roundNum: $wonGift ✓')
                                                      : (isAr ? 'الهدية $roundNum: تم الاختيار ✓' : 'Gift $roundNum: Picked ✓'))
                                                  : isCurrent
                                                      ? (isAr ? 'الهدية $roundNum: اختر الآن 👈' : 'Gift $roundNum: Pick now 👈')
                                                      : (isAr ? 'الهدية $roundNum: في الانتظار ⏳' : 'Gift $roundNum: Waiting ⏳'),
                                              style: GoogleFonts.cairo(
                                                fontSize: isMobile ? 10 : 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: isCompleted || isCurrent ? Colors.white : Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ],

                                // 4. Claimed gifts history summary
                                if (_wonPrizes.isNotEmpty) ...[
                                  SizedBox(height: isMobile ? 10 : 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.inventory_2_rounded, size: 16, color: Colors.green.shade800),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            isAr
                                                ? 'الهدايا المختارة حتى الآن: ${_wonPrizes.join(' + ')}'
                                                : 'Claimed gifts so far: ${_wonPrizes.join(' + ')}',
                                            style: GoogleFonts.cairo(
                                              fontSize: isMobile ? 10.5 : 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          SizedBox(height: isMobile ? 10 : 20),

                          // Responsive Grid of Gift Squares / Cards
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // ALWAYS 2 columns on mobile/phones (2 under 2 under 2 = 6), 3 columns on tablet/desktop!
                              final crossAxisCount = constraints.maxWidth > 700 ? 3 : 2;

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _items.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: isMobile ? 0.78 : 0.85,
                                  crossAxisSpacing: isMobile ? 10 : 16,
                                  mainAxisSpacing: isMobile ? 10 : 16,
                                ),
                                itemBuilder: (context, index) {
                                  final prize = _items[index];
                                  final isSelected = _selectedGiftIndex == index;
                                  final accentColor = _getPrizeAccentColor(context, index);
                                  final prizeIcon = _getPrizeIcon(prize);

                                  return AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) {
                                      final scale = isSelected ? _pulseAnimation.value : 1.0;
                                      return Transform.scale(
                                        scale: scale,
                                        child: child,
                                      );
                                    },
                                    child: InkWell(
                                      onTap: () {
                                        audioService.playWheelTick();
                                        setState(() {
                                          _selectedGiftIndex = index;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(isMobile ? 18 : 22),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        curve: Curves.easeOutCubic,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(isMobile ? 18 : 22),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : Colors.grey.shade200,
                                            width: isSelected ? 2.5 : 1.2,
                                          ),
                                          boxShadow: [
                                            if (isSelected)
                                              BoxShadow(
                                                color: colorScheme.primary.withValues(alpha: 0.22),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4),
                                              )
                                            else
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.04),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                          ],
                                        ),
                                        child: Stack(
                                          children: [
                                            // Main Content: Expanded Product Image + Bottom Details Label
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                // 1. Prominent Product Image filling the upper/center of the card
                                                Expanded(
                                                  child: Center(
                                                    child: Padding(
                                                      padding: EdgeInsets.fromLTRB(
                                                        isMobile ? 12 : 16,
                                                        isMobile ? 14 : 18,
                                                        isMobile ? 12 : 16,
                                                        isMobile ? 8 : 12,
                                                      ),
                                                      child: Builder(
                                                        builder: (context) {
                                                          final prizeImg = _resolvePrizeImage(prize);
                                                          if (prizeImg != null && prizeImg.isNotEmpty) {
                                                            return Image.network(
                                                              prizeImg,
                                                              fit: BoxFit.contain,
                                                              errorBuilder: (context, error, stackTrace) => Container(
                                                                width: isMobile ? 64 : 76,
                                                                height: isMobile ? 64 : 76,
                                                                decoration: BoxDecoration(
                                                                  shape: BoxShape.circle,
                                                                  color: accentColor.withValues(alpha: 0.12),
                                                                ),
                                                                child: Icon(
                                                                  prizeIcon,
                                                                  color: accentColor,
                                                                  size: isMobile ? 32 : 38,
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                          return Container(
                                                            width: isMobile ? 64 : 76,
                                                            height: isMobile ? 64 : 76,
                                                            decoration: BoxDecoration(
                                                              shape: BoxShape.circle,
                                                              color: accentColor.withValues(alpha: 0.12),
                                                            ),
                                                            child: Icon(
                                                              prizeIcon,
                                                              color: accentColor,
                                                              size: isMobile ? 32 : 38,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                // 2. Distinct Bottom Label Panel (Title & Action Button Pill)
                                                AnimatedContainer(
                                                  duration: const Duration(milliseconds: 200),
                                                  width: double.infinity,
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: isMobile ? 8 : 12,
                                                    vertical: isMobile ? 8 : 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? colorScheme.primaryContainer.withValues(alpha: 0.85)
                                                        : const Color(0xFFF8F9FA),
                                                    borderRadius: BorderRadius.vertical(
                                                      bottom: Radius.circular(isMobile ? 16 : 20),
                                                    ),
                                                    border: Border(
                                                      top: BorderSide(
                                                        color: isSelected
                                                            ? colorScheme.primary.withValues(alpha: 0.3)
                                                            : Colors.grey.shade200,
                                                        width: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // Prize Title
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                                        child: Text(
                                                          prize,
                                                          textAlign: TextAlign.center,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: GoogleFonts.cairo(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: isMobile ? 12 : 13.5,
                                                            height: 1.25,
                                                            color: isSelected
                                                                ? colorScheme.primary
                                                                : colorScheme.onSurface,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: isMobile ? 4 : 6),

                                                      // Interactive Action Pill ("اضغط للاختيار" / "تم الاختيار ✓")
                                                      AnimatedContainer(
                                                        duration: const Duration(milliseconds: 200),
                                                        padding: EdgeInsets.symmetric(
                                                          horizontal: isMobile ? 10 : 14,
                                                          vertical: isMobile ? 3 : 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? colorScheme.primary
                                                              : colorScheme.primary.withValues(alpha: 0.08),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? Colors.transparent
                                                                : colorScheme.primary.withValues(alpha: 0.25),
                                                            width: 1,
                                                          ),
                                                          boxShadow: isSelected
                                                              ? [
                                                                  BoxShadow(
                                                                    color: colorScheme.primary.withValues(alpha: 0.3),
                                                                    blurRadius: 6,
                                                                    offset: const Offset(0, 2),
                                                                  ),
                                                                ]
                                                              : null,
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              isSelected ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                                                              size: isMobile ? 12 : 14,
                                                              color: isSelected ? Colors.white : colorScheme.primary,
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Flexible(
                                                              child: Text(
                                                                isSelected
                                                                    ? (totalChances > 1
                                                                        ? (isAr ? 'تم الاختيار (فرصة $_currentRound) ✓' : 'Picked (#$_currentRound) ✓')
                                                                        : (isAr ? 'تم الاختيار ✓' : 'Selected ✓'))
                                                                    : (totalChances > 1
                                                                        ? (isAr ? 'اختيار للفرصة $_currentRound' : 'Pick for #$_currentRound')
                                                                        : (isAr ? 'اضغط للاختيار' : 'Tap to Pick')),
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 1,
                                                                style: GoogleFonts.cairo(
                                                                  fontSize: isMobile ? 9.5 : 11,
                                                                  fontWeight: FontWeight.bold,
                                                                  height: 1.2,
                                                                  color: isSelected ? Colors.white : colorScheme.primary,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // 3. Top Selection Corner Indicator
                                            PositionedDirectional(
                                              top: 10,
                                              end: 10,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                width: isMobile ? 24 : 28,
                                                height: isMobile ? 24 : 28,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : Colors.white.withValues(alpha: 0.85),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? colorScheme.primary
                                                        : Colors.grey.shade300,
                                                    width: 1.5,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: isSelected
                                                          ? colorScheme.primary.withValues(alpha: 0.35)
                                                          : Colors.black.withValues(alpha: 0.06),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 1),
                                                    ),
                                                  ],
                                                ),
                                                child: isSelected
                                                    ? Icon(
                                                        Icons.check_rounded,
                                                        color: Colors.white,
                                                        size: isMobile ? 15 : 18,
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),

                          SizedBox(height: isMobile ? 14 : 36),

                          // SwitchPoint Branding Footer
                          const SwitchPointFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
