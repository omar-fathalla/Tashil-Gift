import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/animations/m3_motion.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../company_portal/domain/whatsapp_gateway_service.dart';
import '../../company_portal/domain/whatsapp_winner_notification_service.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';

class SpinTheWheelScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String eventId;
  final List<String> prizes;
  final int totalChances;
  final bool isDemo;
  final String? branchId;
  final String? customerPhone;
  final String? customerName;
  final bool? enableWhatsAppWinnerNotification;

  const SpinTheWheelScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    this.prizes = const [],
    this.totalChances = 1,
    this.isDemo = false,
    this.branchId,
    this.customerPhone,
    this.customerName,
    this.enableWhatsAppWinnerNotification,
  });

  @override
  ConsumerState<SpinTheWheelScreen> createState() => _SpinTheWheelScreenState();
}

class _SpinTheWheelScreenState extends ConsumerState<SpinTheWheelScreen>
    with SingleTickerProviderStateMixin {
  final StreamController<int> selected = StreamController<int>();
  late final List<String> _items;

  bool _isSpinning = false;
  bool _gamePlayed = false;
  int _prizeIndex = 0;
  late int _remainingChances;
  int _currentRound = 1;
  final List<String> _wonPrizes = [];
  final Map<String, String> _prizeImages = {};
  Timer? _tickTimer;
  bool _whatsappSent = false;
  bool? _enableWhatsAppWinnerNotification;
  String? _resolvedCustomerPhone;

  bool get _isWhatsAppEnabled =>
      _enableWhatsAppWinnerNotification ?? widget.enableWhatsAppWinnerNotification ?? true;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _resolvedCustomerPhone = widget.customerPhone;
    _enableWhatsAppWinnerNotification = widget.enableWhatsAppWinnerNotification;
    _loadPrizeImages();
    _preloadMetadataForWhatsApp();
    _remainingChances = widget.totalChances > 0 ? widget.totalChances : 1;
    final rawList = widget.prizes.isNotEmpty
        ? widget.prizes
        : ['قسيمة شراء 100 ج.م', 'خلاط كهربائي', 'شاشة ذكية', 'طقم حافظات طعام', 'ساعة يد فاخرة', 'كوب حراري'];
    final seen = <String>{};
    _items = rawList.where((p) => p.trim().isNotEmpty && seen.add(p.trim())).toList();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    selected.close();
    _pulseController.dispose();
    super.dispose();
  }

  void _spin() {
    if (_isSpinning || _gamePlayed) return;

    setState(() {
      _isSpinning = true;
    });

    // Start periodic wheel tick audio effects
    _tickTimer?.cancel();
    int ticks = 0;
    _tickTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      ticks++;
      if (ticks > 30 || !_isSpinning || !mounted) {
        timer.cancel();
      } else {
        ref.read(gameAudioServiceProvider).playWheelTick();
      }
    });

    // Randomly select a prize
    _prizeIndex = Random().nextInt(_items.length);
    selected.add(_prizeIndex);
  }

  Future<void> _onSpinEnd(int index) async {
    final prize = _items[index];

    try {
      _remainingChances = (_remainingChances - 1).clamp(0, 999);
      _wonPrizes.add(prize);
      Future<WhatsAppGatewayResult?>? whatsappFuture;

      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'wheel',
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

        // Decrement the prize from the campaign's allocated inventory
        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          await giftsService.decrementCampaignPrize(
            widget.eventId,
            prize,
            branchId: widget.branchId,
            gameType: 'wheel',
          );
        }

        // Dispatch celebratory WhatsApp message when all spins are completed
        if (_remainingChances == 0 && !_whatsappSent) {
          _whatsappSent = true;
          whatsappFuture = _dispatchWhatsAppWinnerNotification();
        }
      }

      if (!mounted) return;

      setState(() {
        _gamePlayed = _remainingChances == 0 && !widget.isDemo;
        _isSpinning = false;
      });

      final imgUrl = _resolvePrizeImage(prize);
      final effectivePhone = (_resolvedCustomerPhone ?? widget.customerPhone ?? '').trim();

      // Trigger the world-class winner celebration dialog
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: prize,
        remainingChances: _remainingChances,
        imageUrl: imgUrl,
        recipientPhone: effectivePhone.isNotEmpty ? effectivePhone : null,
        whatsappDispatchFuture: (_remainingChances == 0 && _isWhatsAppEnabled)
            ? whatsappFuture
            : null,
        onNextChance: () {
          if (!mounted) return;
          setState(() {
            _gamePlayed = false;
            _currentRound++;
          });
        },
        onNextCustomer: () {
          if (!widget.isDemo && !_whatsappSent && _wonPrizes.isNotEmpty) {
            _whatsappSent = true;
            unawaited(_dispatchWhatsAppWinnerNotification());
          }
          // Navigate back to the receipt upload / cashier screen
          Navigator.of(context).pop();
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء تسجيل الجائزة')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      setState(() {
        _isSpinning = false;
      });
    }
  }

  Future<void> _preloadMetadataForWhatsApp() async {
    if (widget.isDemo) return;
    try {
      final firestore = ref.read(firestoreProvider);
      if ((_resolvedCustomerPhone == null || _resolvedCustomerPhone!.trim().isEmpty) &&
          widget.transactionId.isNotEmpty) {
        final txDoc = await firestore.collection('receipts_transactions').doc(widget.transactionId).get();
        if (txDoc.exists && mounted) {
          final data = txDoc.data() ?? {};
          final phone = (data['customerPhone'] ?? data['customer_phone'] ?? data['phone'] ?? '').toString().trim();
          if (phone.isNotEmpty) {
            setState(() => _resolvedCustomerPhone = phone);
          }
        }
      }
      if (_enableWhatsAppWinnerNotification == null && widget.eventId.isNotEmpty) {
        final evDoc = await firestore.collection('events').doc(widget.eventId).get();
        if (evDoc.exists && mounted) {
          final data = evDoc.data() ?? {};
          setState(() {
            _enableWhatsAppWinnerNotification = data['enableWhatsAppWinnerNotification'] != false &&
                data['enable_whatsapp_winner_notification'] != false;
          });
        }
      }
    } catch (_) {}
  }

  Future<WhatsAppGatewayResult?> _dispatchWhatsAppWinnerNotification() async {
    if (!_isWhatsAppEnabled || _wonPrizes.isEmpty) return null;
    return await ref.read(whatsappWinnerNotificationServiceProvider).dispatchForTransaction(
      transactionId: widget.transactionId,
      eventId: widget.eventId,
      prizeName: _wonPrizes.join(' + '),
      customerPhone: _resolvedCustomerPhone ?? widget.customerPhone,
      customerName: widget.customerName,
      isEnabledForCampaign: _isWhatsAppEnabled,
    );
  }

  Future<void> _loadPrizeImages() async {
    try {
      final giftsService = ref.read(companyGiftsServiceProvider);
      final resolved = await giftsService.resolvePrizeImagesForEvent(
        eventId: widget.eventId,
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

  void _resetDemo() {
    setState(() {
      _gamePlayed = false;
      _isSpinning = false;
      _remainingChances = widget.totalChances > 0 ? widget.totalChances : 3;
      _currentRound = 1;
    });
  }

  List<Color> _generateSliceColors(ColorScheme colorScheme) {
    final baseColors = [
      colorScheme.primary,
      colorScheme.tertiary,
      const Color(0xFF6750A4),
      const Color(0xFF006C50),
      const Color(0xFFB3261E),
      const Color(0xFF00639B),
      const Color(0xFF7D5260),
    ];

    List<Color> result = [];
    for (int i = 0; i < _items.length; i++) {
      result.add(baseColors[i % baseColors.length]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sliceColors = _generateSliceColors(colorScheme);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: const SwitchPointHeader(
        subtitle: 'عجلة الحظ التفاعلية — السحب الفوري',
        customActions: [
          GameSoundToggleButton(),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            if (widget.isDemo)
              GameDemoBanner(
                onReset: _resetDemo,
                onExit: () => Navigator.of(context).pop(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Celebratory Header Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primaryContainer.withValues(alpha: 0.8),
                                colorScheme.surfaceContainerHighest,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.stars_rounded, color: colorScheme.primary, size: 28),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'مبروك! لقد تأهلت للسحب الفوري',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.cairo(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.totalChances > 1) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '🎲 الفرصة $_currentRound من إجمالي ${widget.totalChances} فرص (متبقي: $_remainingChances)',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _isSpinning
                                    ? 'العجلة تدور الآن... ترقّب هديتك القيمة!'
                                    : (widget.totalChances > 1
                                        ? 'اسحب العجلة لاستخدام الفرصة رقم ($_currentRound)'
                                        : 'اضغط على زر "لف العجلة" لتدوير العجلة وربح هديتك فوراً'),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 36),

                        // The Fortune Wheel with Glowing Border
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Pulsing Glow
                            Container(
                              width: 370,
                              height: 370,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(alpha: _isSpinning ? 0.35 : 0.15),
                                    blurRadius: _isSpinning ? 40 : 24,
                                    spreadRadius: _isSpinning ? 8 : 2,
                                  ),
                                ],
                              ),
                            ),

                            // Wheel Frame
                            Container(
                              width: 350,
                              height: 350,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFFFD700),
                                  width: 6,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: SelectionContainer.disabled(
                                  child: FortuneWheel(
                                    selected: selected.stream,
                                  duration: const Duration(seconds: 14), // 14 seconds of thrilling, realistic spin
                                  rotationCount: 16, // 16 full revolutions starting fast and decelerating smoothly
                                  curve: FortuneCurve.spin,
                                  indicators: const [
                                    FortuneIndicator(
                                      alignment: Alignment.topCenter,
                                      child: TriangleIndicator(
                                        color: Color(0xFFFFD700),
                                        elevation: 8,
                                      ),
                                    ),
                                  ],
                                  onAnimationEnd: () {
                                    // Pause 600ms on the final winning slice before triggering celebration
                                    Future.delayed(const Duration(milliseconds: 600), () {
                                      _onSpinEnd(_prizeIndex);
                                    });
                                  },
                                  items: [
                                    for (int i = 0; i < _items.length; i++)
                                      FortuneItem(
                                        style: FortuneItemStyle(
                                          color: sliceColors[i],
                                          borderColor: Colors.white.withValues(alpha: 0.4),
                                          borderWidth: 2,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Text(
                                            _items[i],
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                            // Center Golden Hub
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [Color(0xFFFFEA00), Color(0xFFFF8F00)],
                                ),
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.card_giftcard_rounded,
                                size: 26,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 42),

                        // Pulsing / Interactive Spin Button
                        if (!_gamePlayed)
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _isSpinning ? 1.0 : _pulseAnimation.value,
                                child: child,
                              );
                            },
                            child: Tooltip(
                              message: 'اضغط هنا لتدوير العجلة الفائزة',
                              waitDuration: const Duration(milliseconds: 400),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 320),
                                child: M3ActionButton(
                                  label: _isSpinning ? 'العجلة تدور الآن...' : 'لف العجلة واربح!',
                                  icon: _isSpinning ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                                  isLoading: _isSpinning,
                                  variant: M3ButtonVariant.filled,
                                  onPressed: _isSpinning ? null : () async => _spin(),
                                ),
                              ),
                            ),
                          ),

                        if (_gamePlayed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'تم استلام الجائزة بنجاح',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SwitchPointFooter(),
          ],
        ),
      ),
    );
  }
}
