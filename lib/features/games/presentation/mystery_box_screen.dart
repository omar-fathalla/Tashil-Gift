import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/widgets/switch_point_branding.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';

/// Screen displayed when an event uses the "Mystery Box" (الصندوق الغامض) game type.
/// The customer chooses one of three interactive gift boxes to reveal a surprise prize.
class MysteryBoxScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String eventId;
  final List<String> prizes;
  final int totalChances;
  final bool isDemo;

  const MysteryBoxScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    this.prizes = const [],
    this.totalChances = 1,
    this.isDemo = false,
  });

  @override
  ConsumerState<MysteryBoxScreen> createState() => _MysteryBoxScreenState();
}

class _MysteryBoxScreenState extends ConsumerState<MysteryBoxScreen>
    with TickerProviderStateMixin {
  late final List<String> _items;
  int? _selectedBoxIndex;
  bool _isOpening = false;
  bool _isRevealed = false;
  late String _wonPrize;
  late int _remainingChances;
  int _currentRound = 1;
  final List<String> _wonPrizes = [];

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _openController;
  late final Animation<double> _openScaleAnimation;
  late final Animation<double> _prizeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _remainingChances = widget.totalChances > 0 ? widget.totalChances : 1;
    _items = widget.prizes.isNotEmpty
        ? widget.prizes
        : [
            'ساعة ذكية فاخرة',
            'قسيمة مشتريات 150 ج.م',
            'سماعات لاسلكية Pro',
            'ماكينة قهوة اسبريسو',
            'خلاط كهربائي عالي القوة',
            'طقم حافظات حرارية',
          ];

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _openScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _openController, curve: Curves.elasticOut),
    );

    _prizeScaleAnimation = CurvedAnimation(
      parent: _openController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _openController.dispose();
    super.dispose();
  }

  Future<void> _selectBox(int index) async {
    if (_isOpening || _isRevealed) return;

    final audio = ref.read(gameAudioServiceProvider);
    audio.playButtonPop();

    setState(() {
      _selectedBoxIndex = index;
      _isOpening = true;
      _wonPrize = _items[Random().nextInt(_items.length)];
    });

    _pulseController.stop();
    await _openController.forward();

    audio.playGiftUnlock();

    if (!mounted) return;
    setState(() {
      _isRevealed = true;
      _isOpening = false;
    });

    _remainingChances = (_remainingChances - 1).clamp(0, 999);
    _wonPrizes.add(_wonPrize);

    // If not demo mode, persist to Firestore
    if (!widget.isDemo && widget.transactionId.isNotEmpty) {
      try {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'mysteryBox',
          'prize_won': _wonPrizes.join(' + '),
          'prizes_won': _wonPrizes,
          'remaining_chances': _remainingChances,
          'event_id': widget.eventId,
          'claimed_gifts': [{
            'giftId': '',
            'giftName': _wonPrize,
            'quantity': 1,
            'unitValue': 0.0,
            'isVoucher': false,
          }],
        });

        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          await giftsService.decrementCampaignPrize(widget.eventId, _wonPrize);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسجيل الجائزة')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }

    if (!mounted) return;

    // Trigger celebration dialog
    await showWinnerCelebrationDialog(
      context: context,
      prizeName: _wonPrize,
      remainingChances: _remainingChances,
      onNextChance: () {
        if (!mounted) return;
        _resetGame();
      },
      onNextCustomer: () {
        Navigator.of(context).pop();
      },
    );
  }

  void _resetGame() {
    setState(() {
      _selectedBoxIndex = null;
      _isOpening = false;
      _isRevealed = false;
      _currentRound++;
    });
    _openController.reset();
    _pulseController.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: SwitchPointHeader(
        subtitle: strings.mysteryBoxSubtitle,
        customActions: const [
          GameSoundToggleButton(),
        ],
      ),
      body: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            if (widget.isDemo)
              GameDemoBanner(
                onReset: _resetGame,
                onExit: () => Navigator.of(context).pop(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Title & Instructions
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 22),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  strings.mysteryBoxInstruction,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.totalChances > 1) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isAr
                                  ? '🎁 الفرصة $_currentRound من إجمالي ${widget.totalChances} فرص (متبقي: $_remainingChances)'
                                  : '🎁 Chance $_currentRound of ${widget.totalChances} (Remaining: $_remainingChances)',
                              style: GoogleFonts.cairo(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          isAr
                              ? 'فرصتك لاختيار الصندوق الرابح — لمسة واحدة لكشف المفاجأة'
                              : 'Your chance to pick the winning box — tap to reveal the surprise!',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // The 3 Mystery Boxes
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 600;
                            return Flex(
                              direction: isNarrow ? Axis.vertical : Axis.horizontal,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildMysteryBox(
                                  index: 0,
                                  boxName: isAr ? 'الصندوق الأول' : 'Box #1',
                                  gradientColors: [
                                    const Color(0xFF6750A4),
                                    const Color(0xFF7D5260),
                                  ],
                                  accentColor: const Color(0xFFFFD8E4),
                                ),
                                SizedBox(
                                  width: isNarrow ? 0 : 28,
                                  height: isNarrow ? 24 : 0,
                                ),
                                _buildMysteryBox(
                                  index: 1,
                                  boxName: isAr ? 'الصندوق الذهبي' : 'Golden Box',
                                  gradientColors: [
                                    const Color(0xFFD4A017),
                                    const Color(0xFFFF8C00),
                                  ],
                                  accentColor: const Color(0xFFFFF3CD),
                                  isHero: true,
                                ),
                                SizedBox(
                                  width: isNarrow ? 0 : 28,
                                  height: isNarrow ? 24 : 0,
                                ),
                                _buildMysteryBox(
                                  index: 2,
                                  boxName: isAr ? 'الصندوق الثالث' : 'Box #3',
                                  gradientColors: [
                                    const Color(0xFF006C50),
                                    const Color(0xFF00897B),
                                  ],
                                  accentColor: const Color(0xFFC4EED0),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 40),

                        // Action / Helper Buttons
                        if (_isRevealed)
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.replay_rounded),
                                label: Text(
                                  strings.playAgainDemo,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                                onPressed: _resetGame,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: Text(
                                  strings.demoExitBtn,
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMysteryBox({
    required int index,
    required String boxName,
    required List<Color> gradientColors,
    required Color accentColor,
    bool isHero = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedBoxIndex == index;
    final isOtherSelected = _selectedBoxIndex != null && !isSelected;

    Widget boxContent = AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: isOtherSelected ? 0.35 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: isHero ? 220 : 190,
        height: isHero ? 260 : 230,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [colorScheme.primary, colorScheme.tertiary]
                : gradientColors,
          ),
          boxShadow: [
            BoxShadow(
              color: (isSelected ? colorScheme.primary : gradientColors.first).withValues(alpha: 0.35),
              blurRadius: isSelected ? 28 : (isHero ? 20 : 14),
              offset: const Offset(0, 8),
              spreadRadius: isSelected ? 4 : (isHero ? 2 : 0),
            ),
          ],
          border: Border.all(
            color: isSelected ? Colors.white : accentColor.withValues(alpha: 0.6),
            width: isSelected ? 3 : 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected && _isRevealed) ...[
              ScaleTransition(
                scale: _prizeScaleAnimation,
                child: Column(
                  children: [
                    const Icon(Icons.celebration_rounded, color: Colors.amberAccent, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      _wonPrize,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Icon(
                    Icons.card_giftcard_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                boxName,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _selectedBoxIndex == null
                      ? 'اضغط للاختيار'
                      : (isSelected ? 'صندوقك المختار ✨' : 'مغلق'),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (_selectedBoxIndex == null) {
      boxContent = ScaleTransition(
        scale: isHero ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
        child: AnimatedPressable(
          onTap: () => _selectBox(index),
          child: boxContent,
        ),
      );
    } else if (isSelected) {
      boxContent = ScaleTransition(
        scale: _openScaleAnimation,
        child: boxContent,
      );
    }

    return boxContent;
  }
}
