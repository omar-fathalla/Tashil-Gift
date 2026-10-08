import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratcher/scratcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/company_gifts_service.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/switch_point_branding.dart';
import 'winner_celebration_dialog.dart';
import 'game_demo_banner.dart';

class ScratchCardScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String eventId;
  final List<String> prizes;
  final int totalChances;
  final bool isDemo;

  const ScratchCardScreen({
    super.key,
    this.transactionId = '',
    this.eventId = '',
    this.prizes = const [],
    this.totalChances = 1,
    this.isDemo = false,
  });

  @override
  ConsumerState<ScratchCardScreen> createState() => _ScratchCardScreenState();
}

class _ScratchCardScreenState extends ConsumerState<ScratchCardScreen> {
  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();
  double _progress = 0;
  bool _gamePlayed = false;
  late int _remainingChances;
  int _currentRound = 1;
  final List<String> _wonPrizes = [];
  final Map<String, String> _prizeImages = {};

  late final List<String> _items;
  late String _prize;

  @override
  void initState() {
    super.initState();
    _loadPrizeImages();
    _remainingChances = widget.totalChances > 0 ? widget.totalChances : 1;
    final rawList = widget.prizes.isNotEmpty
        ? widget.prizes
        : ['قسيمة شراء 200 ج.م', 'طقم أواني فاخر', 'ماكينة قهوة', 'خلاط كهربائي', 'شاشة ذكية'];
    final seen = <String>{};
    _items = rawList.where((p) => p.trim().isNotEmpty && seen.add(p.trim())).toList();
    _prize = _items[Random().nextInt(_items.length)];
  }

  void _resetDemo() {
    setState(() {
      _gamePlayed = false;
      _progress = 0;
      _remainingChances = widget.totalChances > 0 ? widget.totalChances : 3;
      _currentRound = 1;
      _prize = _items[Random().nextInt(_items.length)];
    });
    _scratcherKey.currentState?.reset();
  }

  Future<void> _onThresholdReached() async {
    if (_gamePlayed) return;

    ref.read(gameAudioServiceProvider).playScratchReveal();

    setState(() {
      _gamePlayed = true;
    });

    try {
      _remainingChances = (_remainingChances - 1).clamp(0, 999);
      _wonPrizes.add(_prize);

      if (!widget.isDemo && widget.transactionId.isNotEmpty) {
        final firestore = ref.read(firestoreProvider);
        await firestore.collection('receipts_transactions').doc(widget.transactionId).update({
          'game_played': true,
          'game_type': 'scratch',
          'prize_won': _wonPrizes.join(' + '),
          'prizes_won': _wonPrizes,
          'remaining_chances': _remainingChances,
          'event_id': widget.eventId,
          'claimed_gifts': [{
            'giftId': '',
            'giftName': _prize,
            'quantity': 1,
            'unitValue': 0.0,
            'isVoucher': false,
          }],
        });

        // Decrement the prize from the campaign's allocated inventory
        if (widget.eventId.isNotEmpty) {
          final giftsService = ref.read(companyGiftsServiceProvider);
          await giftsService.decrementCampaignPrize(widget.eventId, _prize, gameType: 'scratch');
        }
      }

      if (!mounted) return;

      final imgUrl = _resolvePrizeImage(_prize);

      // Trigger world-class winner celebration dialog
      await showWinnerCelebrationDialog(
        context: context,
        prizeName: _prize,
        remainingChances: _remainingChances,
        imageUrl: imgUrl,
        onNextChance: () {
          if (!mounted) return;
          setState(() {
            _gamePlayed = false;
            _progress = 0;
            _currentRound++;
            _prize = _items[Random().nextInt(_items.length)];
          });
          _scratcherKey.currentState?.reset();
        },
        onNextCustomer: () {
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
        _gamePlayed = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: const SwitchPointHeader(
        subtitle: 'بطاقة الخدش والمكافآت الفورية',
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
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Header Card
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
                                  Icon(Icons.workspace_premium_rounded, color: const Color(0xFFFFD700), size: 28),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'أنت عميل مميز! بطاقة الكشط الذهبية',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.cairo(
                                        fontSize: 18,
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
                                    '✨ الفرصة $_currentRound من إجمالي ${widget.totalChances} فرص (متبقي: $_remainingChances)',
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
                                widget.totalChances > 1
                                    ? 'قم بحك البطاقة الفضية لاستخدام الفرصة رقم ($_currentRound)'
                                    : 'قم بحك البطاقة الفضية بيدك لاكتشاف هديتك الفورية',
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

                        // Scratch Card Frame
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFFFD700), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 24,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(21),
                            child: SelectionContainer.disabled(
                              child: Scratcher(
                                key: _scratcherKey,
                                brushSize: 48,
                                threshold: 45,
                                color: const Color(0xFFC0C0C0),
                                onThreshold: () => _onThresholdReached(),
                                onChange: (value) {
                                  setState(() {
                                    _progress = value;
                                  });
                                },
                                child: Container(
                                height: 280,
                                width: 280,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      colorScheme.primaryContainer,
                                      colorScheme.surfaceContainerHighest,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.card_giftcard_rounded,
                                      size: 52,
                                      color: Color(0xFFFF8F00),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _prize,
                                      style: GoogleFonts.cairo(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: colorScheme.primary,
                                        height: 1.3,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                        const SizedBox(height: 24),

                        if (_progress > 0 && !_gamePlayed)
                          Text(
                            'تم كشط ${_progress.toInt()}% من البطاقة...',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
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
