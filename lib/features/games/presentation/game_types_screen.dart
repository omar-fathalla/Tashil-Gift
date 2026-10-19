import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/game_audio_service.dart';
import '../../../core/widgets/game_sound_controls.dart';
import '../../../core/animations/m3_motion.dart';
import '../../admin/domain/event_model.dart';
import 'spin_the_wheel_screen.dart';
import 'scratch_card_screen.dart';
import 'mystery_box_screen.dart';
import 'direct_gift_claim_screen.dart';
import 'choose_gift_screen.dart';

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
                  onPlayDemo: () => _showDirectGiftDemoModal(context, isAr),
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

                const SizedBox(height: 24),

                // Game 5: Choose Your Gift (اختر هديتك - شبكة الاختيارات)
                _buildGameCard(
                  context: context,
                  isAr: isAr,
                  iconContainerColor: colorScheme.primaryContainer,
                  iconColor: colorScheme.primary,
                  icon: Icons.grid_view_rounded,
                  title: strings.gameChooseGiftTitle,
                  subtitle: strings.gameChooseGiftSubtitle,
                  description: strings.gameChooseGiftDesc,
                  onPlayDemo: () {
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const ChooseGiftScreen(
                          totalChances: 2,
                          isDemo: true,
                          prizes: [
                            'ساعة ذكية فاخرة ⌚',
                            'قسيمة مشتريات 150 ج.م 🎟️',
                            'سماعات لاسلكية Pro 🎧',
                            'ماكينة قهوة اسبريسو ☕',
                            'خلاط كهربائي سريع ⚡',
                            'طقم أواني فاخر 🍳',
                          ],
                        ),
                      ),
                    );
                  },
                  onPlaySound: () => audioService.playGiftUnlock(),
                  steps: isAr
                      ? [
                          'يتم إعداد وعرض شبكة بطاقات الهدايا المتوفرة في الحملة والفرع',
                          'يقوم العميل بالاطلاع على خيارات الهدايا المتنوعة',
                          'يختار العميل هديته المفضلة بلمسة واحدة على المربع المخصص',
                          'يتم تأكيد الاختيار وخصم الهدية من رصيد الفرع فورياً',
                        ]
                      : [
                          'A curated grid of available campaign gifts is displayed',
                          'Customer explores the variety of designated rewards',
                          'Customer picks their favorite reward with a single tap on the card',
                          'Selection is confirmed and deducted from branch stock in real-time',
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

  static void _showDirectGiftDemoModal(BuildContext context, bool isAr) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // Title Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.redeem_rounded, color: colorScheme.secondary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? 'اختر سيناريو الديمو للهدية الفورية' : 'Select Direct Gift Demo Scenario',
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            isAr ? 'معاينة تجربة العميل لحالات الفوز الفردي والمضاعف والسلة المجمعة' : 'Preview Single Win, Multipliers & Multi-Offer Bundles',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Scenario 1: Single Win (فوز فردي بسيط)
                _DemoScenarioTile(
                  icon: Icons.confirmation_number_rounded,
                  iconColor: colorScheme.primary,
                  iconBg: colorScheme.primaryContainer,
                  title: isAr ? '1. فوز فردي بسيط (Single Win)' : '1. Single Win (1 Gift)',
                  subtitle: isAr ? 'فوز بـ 1 × فواتشر مشتريات 50 ج.م' : 'Customer won 1 × 50 EGP Voucher',
                  badgeText: isAr ? 'عرض مفرد' : 'Single Offer',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const DirectGiftClaimScreen(
                          prizeName: 'فواتشر مشتريات بقيمة 50 جنيه',
                          unitValue: 50.0,
                          isVoucher: true,
                          quantity: 1,
                          isDemo: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Scenario 2: Multi-Quantity Win (مضاعفة كمية العرض)
                _DemoScenarioTile(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: colorScheme.secondary,
                  iconBg: colorScheme.secondaryContainer,
                  title: isAr ? '2. مضاعفة كمية العرض (Multi-Quantity 2×)' : '2. Multi-Quantity (2× Offer)',
                  subtitle: isAr ? 'شراء 4 قطع ➔ 2 × فواتشر 125 ج.م (إجمالي 250 ج.م)' : 'Customer won 2 × 125 EGP Voucher (Total 250 EGP)',
                  badgeText: isAr ? 'مضاعفة ×2' : 'Multiplier 2×',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const DirectGiftClaimScreen(
                          prizeName: 'فواتشر بقيمة 125 جنيه',
                          unitValue: 125.0,
                          isVoucher: true,
                          quantity: 2,
                          isDemo: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Scenario 3: Multi-Offer Bundle Win (سلة هدايا مجمعة - متعدد الشروط)
                _DemoScenarioTile(
                  icon: Icons.inventory_2_rounded,
                  iconColor: colorScheme.tertiary,
                  iconBg: colorScheme.tertiaryContainer,
                  title: isAr ? '3. سلة هدايا مجمعة (Multi-Offer Bundle)' : '3. Multi-Offer Gift Bundle',
                  subtitle: isAr ? 'استيفاء 3 شروط: فواتشر 50 ج.م + كلير 90 مل + تريزيمي 250 مل' : 'Met 3 conditions: 50 EGP Voucher + Clear 90ml + Tresemme 250ml',
                  badgeText: isAr ? '3 هدايا مجمعة' : '3 Gifts Bundle',
                  isHighlighted: true,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: DirectGiftClaimScreen(
                          prizeName: 'فواتشر 50 جنيه + كلير 90 مل هدية + تريزيمي 250 مل هدية',
                          isVoucher: true,
                          quantity: 1,
                          isDemo: true,
                          linkedGifts: [
                            LinkedGiftAllocation(
                              giftId: 'voucher_50',
                              giftName: 'فواتشر مشتريات 50 ج.م',
                              quantity: 1,
                              unitValue: 50.0,
                              giftType: 'voucher',
                            ),
                            LinkedGiftAllocation(
                              giftId: 'clear_90',
                              giftName: 'شامبو كلير 90 مل هدية',
                              quantity: 1,
                              unitValue: 0.0,
                              giftType: 'product',
                            ),
                            LinkedGiftAllocation(
                              giftId: 'tresemme_250',
                              giftName: 'تريزيمي 250 مل هدية',
                              quantity: 1,
                              unitValue: 0.0,
                              giftType: 'product',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Scenario 4: Single Physical Product (هدية عينية فردية)
                _DemoScenarioTile(
                  icon: Icons.card_giftcard_rounded,
                  iconColor: colorScheme.onPrimaryContainer,
                  iconBg: colorScheme.primaryContainer,
                  title: isAr ? '4. هدية عينية ترويجية (Physical Product)' : '4. Certified Physical Gift',
                  subtitle: isAr ? 'فوز بـ 1 × تريزيمي 250 مل هدية' : 'Customer won 1 × Tresemme 250ml Gift',
                  badgeText: isAr ? 'هدية عينية' : 'Physical Gift',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      M3PageRoute(
                        page: const DirectGiftClaimScreen(
                          prizeName: 'تريزيمي 250 مل هدية',
                          isVoucher: false,
                          quantity: 1,
                          isDemo: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
    String? demoButtonLabel,
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
                      customLabel: demoButtonLabel,
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
  final String? customLabel;

  const _GameDemoLaunchButton({
    required this.isAr,
    required this.onPressed,
    required this.gameTitle,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton.icon(
      icon: const Icon(Icons.sports_esports_rounded, size: 18),
      label: Text(
        customLabel ?? (isAr ? 'تجربة اللعبة (ديمو تفاعلي)' : 'Play Game Demo (Live)'),
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

class _DemoScenarioTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String badgeText;
  final VoidCallback onTap;
  final bool isHighlighted;

  const _DemoScenarioTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isHighlighted
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHighlighted
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isHighlighted ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isHighlighted ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isHighlighted ? Colors.white : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, color: colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
