import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_emulator_config.dart';
import '../../../core/services/firebase_service.dart';
import '../../auth/presentation/auth_screen.dart';
import 'choose_gift_screen.dart';

/// Opens the gift screen for a receipt id this app never creates.
///
/// Only an emulator build whose Firebase project id starts with `demo-`
/// reaches the gift screen. A production build shows a static refusal and
/// does not read Firestore. The id is not deleted or overwritten here.
class EmulatorMissingLedgerProbeScreen extends ConsumerWidget {
  const EmulatorMissingLedgerProbeScreen({super.key});

  static const String route = '/demo-ledger-missing';
  static const String receiptId = 'rcpt_demo_missing_ledger_probe';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kFirebaseEmulator) {
      return const Scaffold(
        body: Center(
          child: Text('This ledger probe is available only in the local emulator build.'),
        ),
      );
    }
    final project = Firebase.apps.isEmpty ? '' : Firebase.app().options.projectId;
    if (!project.startsWith('demo-')) {
      return const Scaffold(
        body: Center(
          child: Text('This ledger probe requires a demo- Firebase project.'),
        ),
      );
    }
    if (!ref.watch(isAdminProvider)) {
      return const AuthScreen();
    }
    return const ChooseGiftScreen(
      transactionId: receiptId,
      eventId: 'demo-ledger-probe',
      totalChances: 1,
      roundPrizeNames: [
        ['probe'],
      ],
      roundGiftIds: [
        ['probe-gift'],
      ],
    );
  }
}
