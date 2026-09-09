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
  final List<String> prizes;
  final int totalChances;
  final bool isDemo;
  final String? branchId;

  const ChooseGiftScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    this.prizes = const [],
    this.totalChances = 1,
    this.isDemo = false,
    this.branchId,
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

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _remainingChances = widget.totalChances > 0 ? widget.totalChances : 1;
    _items = widget.prizes.isNotEmpty
        ? widget.prizes
        : [
            'ساعة ذكية فاخرة ⌚',
            'قسيمة مشتريات 150 ج.م 🎟️',
            'سماعات لاسلكية Pro 🎧',
            'ماكينة قهوة اسبريسو ☕',
            'خلاط كهربائي سريع ⚡',
            'طقم أواني فاخر 🍳',
          ];

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
          await giftsService.decrementCampaignPrize(widget.eventId, selectedPrize);
        }
      }

      if (!mounted) return;

      await showWinnerCelebrationDialog(
        context: context,
        prizeName: selectedPrize,
        remainingChances: _remainingChances,
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

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            strings.gameChooseGiftTitle,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: const [
            GameSoundToggleButton(),
            SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: _selectedGiftIndex != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                              isAr ? 'الهدية المختارة حالياً:' : 'Currently Selected Gift:',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _items[_selectedGiftIndex!],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        icon: _isConfirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isConfirming
                              ? (isAr ? 'جاري التأكيد...' : 'Confirming...')
                              : (isAr ? 'تأكيد الهدية 🎁' : 'Confirm Gift 🎁'),
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                  padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 32.0),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        children: [
                          // Status & Chance Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primaryContainer.withValues(alpha: 0.8),
                                  colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.touch_app_rounded, color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        totalChances > 1
                                            ? (isAr
                                                ? 'الفرصة $_currentRound من إجمالي $totalChances فرص'
                                                : 'Chance #$_currentRound of $totalChances chances')
                                            : strings.chooseYourGiftPrompt,
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        isAr
                                            ? 'اختر الهدية التي تفضلها من المربعات بالأسفل واضغط تأكيد'
                                            : 'Tap your preferred reward from the cards below and confirm',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (totalChances > 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isAr ? '$_remainingChances متبقية' : '$_remainingChances left',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Responsive Grid of Gift Squares / Cards
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount = constraints.maxWidth > 650
                                  ? 3
                                  : (constraints.maxWidth > 400 ? 2 : 1);

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _items.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: constraints.maxWidth > 650 ? 1.05 : 1.15,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
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
                                      borderRadius: BorderRadius.circular(24),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                                              : colorScheme.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant.withValues(alpha: 0.6),
                                            width: isSelected ? 2.5 : 1.0,
                                          ),
                                          boxShadow: [
                                            if (isSelected)
                                              BoxShadow(
                                                color: colorScheme.primary.withValues(alpha: 0.25),
                                                blurRadius: 18,
                                                offset: const Offset(0, 6),
                                              )
                                            else
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.03),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            // Top Selection Checkmark
                                            Align(
                                              alignment: Alignment.topRight,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : Colors.transparent,
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? colorScheme.primary
                                                        : colorScheme.outlineVariant,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: isSelected
                                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                                    : null,
                                              ),
                                            ),

                                            const Spacer(),

                                            // Prize Icon
                                            Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: accentColor.withValues(alpha: 0.12),
                                              ),
                                              child: Icon(
                                                prizeIcon,
                                                color: accentColor,
                                                size: 32,
                                              ),
                                            ),

                                            const SizedBox(height: 14),

                                            // Prize Title
                                            Text(
                                              prize,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.cairo(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isSelected
                                                    ? colorScheme.primary
                                                    : colorScheme.onSurface,
                                              ),
                                            ),

                                            const Spacer(),

                                            // Badge / Prompt
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? colorScheme.primary.withValues(alpha: 0.12)
                                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                isSelected
                                                    ? (isAr ? 'تم الاختيار ✓' : 'Selected ✓')
                                                    : (isAr ? 'اضغط للاختيار' : 'Tap to Pick'),
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  color: isSelected
                                                      ? colorScheme.primary
                                                      : colorScheme.onSurfaceVariant,
                                                ),
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

                          const SizedBox(height: 36),

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
    );
  }
}
