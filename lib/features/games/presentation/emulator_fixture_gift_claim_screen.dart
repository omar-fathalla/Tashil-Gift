import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_emulator_config.dart';
import '../../../core/services/firebase_service.dart';
import '../../admin/domain/event_model.dart';
import '../../auth/presentation/auth_screen.dart';
import 'direct_gift_claim_screen.dart';

/// Local-emulator claim for the synthetic store-243 receipt.
///
/// The route is registered in every build so a tester can open the same path.
/// The claim screen is created only when [kFirebaseEmulator] is true, and only
/// once, so a rebuild does not decrement the fixture stock again.
class EmulatorFixtureGiftClaimScreen extends ConsumerStatefulWidget {
  const EmulatorFixtureGiftClaimScreen({super.key});

  static const String route = '/fixture-gift';
  static const String eventId = 'fixture-order-a';
  static const String receiptId = 'a-code-243';
  static const String branchId = 'fathalla_243';
  static const String outletGiftId = 'gift-outlet-243';
  static const String outletGiftName = 'هدية أوتليت طنطا';
  static const String shortGiftId = 'gift-short-231';
  static const String shortBranchName = 'فرع طنطا (الغربية)';

  @override
  ConsumerState<EmulatorFixtureGiftClaimScreen> createState() =>
      _EmulatorFixtureGiftClaimScreenState();
}

class _EmulatorFixtureGiftClaimScreenState
    extends ConsumerState<EmulatorFixtureGiftClaimScreen> {
  Widget? _claim;

  @override
  Widget build(BuildContext context) {
    if (!kFirebaseEmulator) {
      return const Scaffold(
        body: Center(
          child: Text(
            'This gift route is available only in the local emulator build.',
          ),
        ),
      );
    }
    if (!ref.watch(isAdminProvider)) {
      return const AuthScreen();
    }
    _claim ??= DirectGiftClaimScreen(
      key: const ValueKey('fixture-gift-fathalla-243'),
      transactionId: EmulatorFixtureGiftClaimScreen.receiptId,
      eventId: EmulatorFixtureGiftClaimScreen.eventId,
      prizeName: EmulatorFixtureGiftClaimScreen.outletGiftName,
      quantity: 1,
      branchId: EmulatorFixtureGiftClaimScreen.branchId,
      branchName: EmulatorFixtureGiftClaimScreen.shortBranchName,
      linkedGifts: [
        LinkedGiftAllocation(
          giftId: EmulatorFixtureGiftClaimScreen.outletGiftId,
          giftName: EmulatorFixtureGiftClaimScreen.outletGiftName,
          quantity: 1,
          giftType: 'product',
        ),
      ],
      customerName: 'Synthetic Customer',
      customerPhone: '01000000000',
      receiptNumber: '137/4/243/061126',
      companySlug: 'fixture-co',
      enableWhatsAppWinnerNotification: false,
    );
    return _claim!;
  }
}
