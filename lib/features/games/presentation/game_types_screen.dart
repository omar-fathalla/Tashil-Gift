import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/animations/m3_motion.dart';
import 'spin_the_wheel_screen.dart';
import 'scratch_card_screen.dart';
import 'mystery_box_screen.dart';
import 'direct_gift_claim_screen.dart';

class GameTypesScreen extends ConsumerWidget {
  const GameTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);
    final audioService = ref.watch(gameAudioServiceProvider);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 36.0, 24.0, 48.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Page Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.videogame_asset_rounded, color: colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.gameTypesTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            strings.gameTypesSubtitle,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const GameSoundToggleButton(),
                  ],
                ),
                const SizedBox(height: 20),

                // Material 3 Sound System Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.volume_up_rounded, color: colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'نظام المؤثرات الصوتية التفاعلية (Google Sound Engine)' : 'Google Material Audio Engine Active',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              isAr ? 'مؤثرات صوتية ولمسية فائقة السرعة مدمجة مع كافة الألعاب والمسابقات' : 'Low-latency haptic audio synthesized for all interactive games',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(isAr ? 'إعدادات الصوت' : 'Audio Settings', style: GoogleFonts.cairo(fontSize: 12)),
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const GameSoundSettingsBottomSheet(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Game 1: Spin the Wheel
                _buildGameCard(
                  context: context,
                  isAr: isAr,
                  iconContainerColor: colorScheme.primaryContainer,
                  iconColor: colorScheme.primary,
                  icon: Icons.casino_rounded,
                  title: isAr ? 'عجلة الحظ' : 'Spin the Wheel',
                  subtitle: isAr ? 'Spin the Wheel' : 'Circular Animated Prize Wheel',
                  description: strings.gameWheelDesc,
                  onPlayDemo: () {
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const SpinTheWheelScreen(
                          totalChances: 3,
                          isDemo: true,
                          prizes: [
                            'قسيمة شراء 500 ج.م 🎟️',
                            'شاشة تلفزيون 55 بوصة 📺',
                            'ماكينة قهوة اسبريسو ☕',
                            'قسيمة شراء 200 ج.م 🎟️',
                            'سماعات لاسلكية Pro 🎧',
                            'طقم أواني فاخر 🍳',
                            'خلاط كهربائي سريع ⚡',
                            'ساعة ذكية رياضية ⌚',
                          ],
                        ),
                      ),
                    );
                  },
                  onPlaySound: () => audioService.playWheelTick(),
                  steps: isAr
                      ? [
                          'يتم تحميل الهدايا المخصصة للحملة/الفرع على أقسام العجلة',
                          'يقوم العميل بالضغط على زر التدوير',
                          'تدور العجلة وتتوقف عشوائياً على هدية',
                          'يتم تسجيل الفوز وخصم الهدية من رصيد الفرع',
                        ]
                      : [
                          'Configured promotional gifts are loaded onto wheel segments',
                          'Customer taps the spin button to activate the animation',
                          'Wheel spins and lands dynamically on a winning reward',
                          'Win is verified and prize quantity is deducted in real-time',
                        ],
                  badgeText: isAr ? 'متاحة للاستخدام' : 'Active & Ready',
                  badgeColor: colorScheme.secondaryContainer,
                  badgeTextColor: colorScheme.onSecondaryContainer,
                ),
                
                const SizedBox(height: 24),

                // Game 2: Scratch & Win
                _buildGameCard(
                  context: context,
                  isAr: isAr,
                  iconContainerColor: colorScheme.tertiaryContainer,
                  iconColor: colorScheme.tertiary,
                  icon: Icons.style_rounded,
                  title: isAr ? 'امسح واربح' : 'Scratch & Win',
                  subtitle: isAr ? 'Scratch & Win' : 'Digital Interactive Scratch Card',
                  description: strings.gameScratchDesc,
                  onPlayDemo: () {
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const ScratchCardScreen(
                          totalChances: 3,
                          isDemo: true,
                          prizes: [
                            'قسيمة خصم 300 ج.م 🎁',
                            'ساعة ذكية حديثة ⌚',
                            'ماكينة تحضير قهوة ☕',
                            'طقم حافظات طعام حراري 🍲',
                            'قسيمة شراء 150 ج.م 🎟️',
                          ],
                        ),
                      ),
                    );
                  },
                  onPlaySound: () => audioService.playScratchReveal(),
                  steps: isAr
                      ? [
                          'يتم اختيار هدية عشوائية من الهدايا المخصصة للحملة',
                          'تظهر بطاقة مغطاة بطبقة رمادية',
                          'يقوم العميل بالخدش (السحب بالإصبع) لكشف الهدية',
                          'عند كشف 50% من البطاقة، يتم تأكيد الفوز وتسجيله',
                        ]
                      : [
                          'A prize is selected dynamically based on probability weights',
                          'A digital scratch card appears with an opaque scratch coating',
                          'Customer rubs the screen with touch gestures to reveal the gift',
                          'Upon 50% uncover, victory is confirmed and prize is awarded',
                        ],
                  badgeText: isAr ? 'متاحة للاستخدام' : 'Active & Ready',
                  badgeColor: colorScheme.secondaryContainer,
                  badgeTextColor: colorScheme.onSecondaryContainer,
                ),

                const SizedBox(height: 24),

                // Game 3: Mystery Box
                _buildGameCard(
                  context: context,
                  isAr: isAr,
                  iconContainerColor: colorScheme.primaryContainer,
                  iconColor: colorScheme.primary,
                  icon: Icons.card_giftcard_rounded,
                  title: isAr ? 'الصندوق الغامض' : 'Mystery Box',
                  subtitle: isAr ? 'Mystery Box' : 'Pick One of Three Mystery Gift Boxes',
                  description: strings.gameBoxDesc,
                  onPlayDemo: () {
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const MysteryBoxScreen(
                          totalChances: 3,
                          isDemo: true,
                          prizes: [
                            'ساعة ذكية فاخرة ⌚',
                            'قسيمة مشتريات 500 ج.م 🎟️',
                            'سماعات بلوتوث عازلة للصوت 🎧',
                            'طقم أدوات منزلية راقي 🏠',
                            'ماكينة اسبريسو إيطالية ☕',
                          ],
                        ),
                      ),
                    );
                  },
                  onPlaySound: () => audioService.playGiftUnlock(),
                  steps: isAr
                      ? [
                          'تظهر ثلاثة صناديق هدايا تفاعلية على الشاشة',
                          'يختار العميل أحد الصناديق بلمسة واحدة',
                          'يفتح الصندوق مع تأثيرات بصرية وصوتية لكشف الجائزة',
                          'يتم حفظ نتيجة الفوز الفوري في قاعدة البيانات',
                        ]
                      : [
                          'Three 3D animated mystery gift boxes appear on the screen',
                          'Customer taps their favorite mystery box to choose',
                          'Box bursts open with confetti and sound effects revealing the gift',
                          'Prize claim voucher is created and saved immediately',
                        ],
                  badgeText: isAr ? 'متاحة للاستخدام' : 'Active & Ready',
                  badgeColor: colorScheme.secondaryContainer,
                  badgeTextColor: colorScheme.onSecondaryContainer,
                ),

                const SizedBox(height: 24),

                // Game 4: Direct Instant Gift (الهدية الفورية المباشرة)
                _buildGameCard(
                  context: context,
                  isAr: isAr,
                  iconContainerColor: colorScheme.secondaryContainer,
                  iconColor: colorScheme.secondary,
                  icon: Icons.redeem_rounded,
                  title: strings.gameDirectGiftTitle,
                  subtitle: strings.gameDirectGiftSubtitle,
                  description: strings.gameDirectGiftDesc,
                  onPlayDemo: () {
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const DirectGiftClaimScreen(
                          prizeName: 'طقم هدايا ترويجية VIP فاخر ✨',
                          quantity: 2,
                          isDemo: true,
                        ),
                      ),
                    );
                  },
                  onPlaySound: () => audioService.playGiftUnlock(),
                  steps: isAr
                      ? [
                          'يتم تحديد الهدية الترويجية الثابتة المخصصة للحملة ورصيدها المتاح',
                          'يقوم الذكاء الاصطناعي بفحص الفاتورة والتأكد من مطابقة شروط الشراء',
                          'تظهر شاشة استلام الهدية مباشرة للعميل مع احتساب الكمية تلقائياً',
                          'يتم خصم الكمية من رصيد الفرع وتسليم الهدية للعميل وتوثيق الفاتورة',
                        ]
                      : [
                          'Designated promotional gift and allocated quantity are configured for the event',
                          'AI analyzes the receipt to verify eligibility and product purchase conditions',
                          'Direct Gift Claim screen opens immediately with automatic quantity calculation',
                          'Gift stock is deducted from branch inventory and handover is logged in real-time',
                        ],
                  badgeText: isAr ? 'متاحة للاستخدام' : 'Active & Ready',
                  badgeColor: colorScheme.secondaryContainer,
                  badgeTextColor: colorScheme.onSecondaryContainer,
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameCard({
    required BuildContext context,
    required bool isAr,
    required Color iconContainerColor,
    required Color iconColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required List<String> steps,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    VoidCallback? onPlayDemo,
    VoidCallback? onPlaySound,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconContainerColor.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title, 
                        style: GoogleFonts.cairo(
                          fontSize: 20, 
                          fontWeight: FontWeight.bold, 
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle, 
                        style: GoogleFonts.cairo(
                          fontSize: 14, 
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              description,
              style: GoogleFonts.cairo(
                fontSize: 15,
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'آلية العمل:' : 'How It Works:',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...steps.asMap().entries.map((entry) {
                    int index = entry.key;
                    String step = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            if (onPlayDemo != null || onPlaySound != null) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: isAr ? WrapAlignment.start : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onPlayDemo != null)
                    _GameDemoLaunchButton(
                      isAr: isAr,
                      onPressed: onPlayDemo,
                      gameTitle: title,
                    ),
                  if (onPlaySound != null)
                    _GameSoundPreviewButton(
                      isAr: isAr,
                      onPlaySound: onPlaySound,
                      gameTitle: title,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameDemoLaunchButton extends StatelessWidget {
  final bool isAr;
  final VoidCallback onPressed;
  final String gameTitle;

  const _GameDemoLaunchButton({
    required this.isAr,
    required this.onPressed,
    required this.gameTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton.icon(
      icon: const Icon(Icons.sports_esports_rounded, size: 18),
      label: Text(
        isAr ? 'تجربة اللعبة (ديمو تفاعلي)' : 'Play Game Demo (Live)',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        elevation: 1,
      ),
      onPressed: onPressed,
    );
  }
}

class _GameSoundPreviewButton extends StatefulWidget {
  final bool isAr;
  final VoidCallback onPlaySound;
  final String gameTitle;

  const _GameSoundPreviewButton({
    required this.isAr,
    required this.onPlaySound,
    required this.gameTitle,
  });

  @override
  State<_GameSoundPreviewButton> createState() => _GameSoundPreviewButtonState();
}

class _GameSoundPreviewButtonState extends State<_GameSoundPreviewButton> {
  bool _isPlaying = false;

  void _triggerPlay() {
    setState(() => _isPlaying = true);
    widget.onPlaySound();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isPlaying
            ? Icon(Icons.graphic_eq_rounded, key: const ValueKey('eq'), size: 18, color: colorScheme.primary)
            : Icon(Icons.volume_up_rounded, key: const ValueKey('vol'), size: 18, color: colorScheme.onSurfaceVariant),
      ),
      label: Text(
        _isPlaying
            ? (widget.isAr ? 'جاري التشغيل... 🎵' : 'Playing Sound... 🎵')
            : (widget.isAr ? 'تجربة المؤثرات الصوتية' : 'Preview Game Sound Effects'),
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: _isPlaying ? colorScheme.primary : null,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: _isPlaying ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        side: BorderSide(color: _isPlaying ? colorScheme.primary : colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: _triggerPlay,
    );
  }
}
