// Guard and analysis checks for the synthetic image. This file does not drive
// the upload screen and does not write a receipt. The screen runner is
// tool/consuming_upload_ui_runner.mjs.
//
//   flutter test test/synthetic_receipt_pipeline_test.dart
//   flutter test --dart-define=FIREBASE_EMULATOR=true \
//     --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
//     test/synthetic_receipt_pipeline_test.dart

import 'package:al_mraay/core/services/accepted_receipt_core.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/core/services/firebase_emulator_config.dart';
import 'package:al_mraay/core/services/synthetic_receipt_fixture.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/games/presentation/choose_gift_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const gift500 = '4QDy4H8psECEP4AnJSON';
const gift350 = 'beGiYXcMAsW78OGevW5d';

PromotionalRuleItem tier(String id, double min, String giftId, double amount) {
  return PromotionalRuleItem(
    id: id,
    ruleTitle: 'شريحة ${min.toInt()}',
    triggerProduct: 'كادبري',
    conditionType: 'by_spend',
    minSpend: min,
    rewardType: 'voucher',
    rewardValue: 'قسيمة شراء ${amount.toInt()} جنيه',
    rewardAmount: amount,
    requiredBrands: const ['كادبري'],
    selectedBarcodes: const ['6220000000011'],
    rewardOptions: [
      RewardOption(
        id: 'opt-$id',
        kind: 'voucher',
        giftId: giftId,
        giftType: 'voucher',
        voucherAmount: amount,
        label: 'قسيمة شراء ${amount.toInt()} جنيه',
      ),
    ],
  );
}

final rules = [
  tier('tier-200', 200, 'gift-200', 50),
  tier('tier-350', 350, gift350, 100),
  tier('tier-500', 500, gift500, 150),
];

EventModel campaign({int cap = 3}) {
  return EventModel(
    id: 'fixture-consuming-upload',
    eventName: 'اختبار السلم',
    targetCompany: 'كادبري',
    companySlug: 'fixture-co',
    minimumSpend: 200,
    promotionalRules: rules,
    gameType: 'chooseGift',
    allowMultipleChances: true,
    maxChancesPerReceipt: cap,
    spendLadderMode: 'consuming',
    retailChainName: 'سلسلة الاختبار',
    branchNames: const ['فرع الاختبار'],
  );
}

Future<AiReceiptAnalysisResult> analyze(int cap) {
  return AiReceiptService().analyzeReceiptImage(
    SyntheticReceiptFixture.imageBytes,
    'image/jpeg',
    targetCompany: 'كادبري',
    minimumSpend: 200,
    requiredProducts: const ['كادبري'],
    promotionalRules: rules,
    allowMultipleChances: true,
    maxChancesPerReceipt: cap,
    spendLadderMode: 'consuming',
  );
}

class _EchoFirebase implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: initializeAppRequest,
      pluginConstants: const {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => const [];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async {
    return CoreFirebaseOptions(
      apiKey: 'demo',
      appId: '1:0:web:demo',
      messagingSenderId: '0',
      projectId: 'demo-tashil-branch',
    );
  }
}

Future<void> useFirebaseProject(String projectId) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_EchoFirebase());
  if (Firebase.apps.isNotEmpty) {
    if (Firebase.app().options.projectId == projectId) return;
    throw StateError('Firebase is already ${Firebase.app().options.projectId}');
  }
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: 'demo',
      appId: '1:0:web:demo',
      messagingSenderId: '0',
      projectId: projectId,
    ),
  );
}

void main() {
  test('synthetic fixture stays closed for the four guard cases', () {
    const host = '127.0.0.1';
    expect(
      syntheticReceiptMayServe(
        emulatorBuild: true,
        fixtureRequested: true,
        firebaseReady: false,
        projectId: 'demo-tashil-branch',
        emulatorHost: host,
      ),
      isFalse,
    );
    expect(
      syntheticReceiptMayServe(
        emulatorBuild: true,
        fixtureRequested: true,
        firebaseReady: true,
        projectId: 'tashil-gift',
        emulatorHost: host,
      ),
      isFalse,
    );
    expect(
      syntheticReceiptMayServe(
        emulatorBuild: false,
        fixtureRequested: false,
        firebaseReady: true,
        projectId: 'demo-tashil-branch',
        emulatorHost: host,
      ),
      isFalse,
    );
    expect(
      syntheticReceiptMayServe(
        emulatorBuild: true,
        fixtureRequested: true,
        firebaseReady: true,
        projectId: 'demo-tashil-branch',
        emulatorHost: '8.8.8.8',
      ),
      isFalse,
    );
    expect(
      syntheticReceiptMayServe(
        emulatorBuild: true,
        fixtureRequested: true,
        firebaseReady: true,
        projectId: 'demo-tashil-branch',
        emulatorHost: host,
      ),
      isTrue,
    );
  });

  test('no Firebase app rejects the fixture before any project exists', () {
    expect(SyntheticReceiptFixture.enabled, isFalse);
    expect(SyntheticReceiptFixture.modelTextFor(SyntheticReceiptFixture.imageBytes), isNull);
  });

  test('a normal build rejects the fixture even after a demo app exists', () async {
    if (kFirebaseEmulator && kSyntheticReceiptFixture) return;
    await useFirebaseProject('demo-tashil-branch');
    expect(SyntheticReceiptFixture.enabled, isFalse);
    expect(SyntheticReceiptFixture.modelTextFor(SyntheticReceiptFixture.imageBytes), isNull);
  });

  test('fixture bytes travel through production analysis and the shared save fields', () async {
    if (!kFirebaseEmulator || !kSyntheticReceiptFixture) return;
    await useFirebaseProject('demo-tashil-branch');
    expect(SyntheticReceiptFixture.enabled, isTrue);

    final result = await analyze(3);
    expect(result.pipelineTierUsed, 'synthetic_fixture');
    expect(result.extractedProducts.map((item) => item.name), contains('لارش كيك ميلت شوك'));
    expect(result.chancesEarned, 3);

    final matched = PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'consuming',
    );
    final rounds = SpendAwardRound.expand(matched);
    expect(rounds.map((round) => round.tierMinSpend), [500, 500, 350]);
    expect(rounds.map((round) => round.giftIds.single), [gift500, gift500, gift350]);

    final capped = await analyze(2);
    expect(capped.chancesEarned, 2);

    final summary = MultiCampaignReceiptEvaluator.evaluateAll(
      result: result,
      campaigns: [campaign()],
    );
    final winning = summary.qualifiedCampaigns.single;
    expect(winning.totalChances, 3);
    expect(
      SpendAwardRound.expand(winning.matchedRules).map((round) => round.tierMinSpend),
      [500, 500, 350],
    );

    final saved = acceptedReceiptCore(
      result: result,
      campaignId: campaign().id,
      companySlug: 'fixture-co',
      targetCompany: 'كادبري',
      retailChainName: 'سلسلة الاختبار',
      chancesEarned: winning.totalChances,
      allowMultipleChances: true,
      submittedByUid: 'fixture-user',
      branchFields: const {'branch_detected': 'فرع الاختبار'},
    );
    final reloaded = (saved['extracted_products'] as List)
        .map((item) => ExtractedProductItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    expect(reloaded.map((item) => item.name), contains('لارش كيك ميلت شوك'));
    final recheck = AiReceiptAnalysisResult(
      isValid: true,
      receiptNumber: saved['receipt_number'] as String,
      targetCompanyTotal: (saved['target_company_total'] as num).toDouble(),
      receiptDate: saved['receipt_date'] as String,
      extractedProducts: reloaded,
      storeChainDetected: saved['store_chain_detected'] as String,
      branchDetected: 'فرع الاختبار',
      message: 'recheck',
      durationMs: 0,
    );
    final again = MultiCampaignReceiptEvaluator.evaluateAll(
      result: recheck,
      campaigns: [campaign()],
    );
    expect(
      SpendAwardRound.expand(again.qualifiedCampaigns.single.matchedRules).map((round) => round.unitValues.single),
      [150, 150, 100],
    );
  });

  testWidgets('analyzed round labels render on the gift screen without confirming a claim', (tester) async {
    if (!kFirebaseEmulator || !kSyntheticReceiptFixture) return;
    await useFirebaseProject('demo-tashil-branch');
    final result = await analyze(3);
    final rounds = SpendAwardRound.expand(PromotionalRuleMatcher.matchAllWithMultipliers(
      result: result,
      promotionalRules: rules,
      allowCampaignMultipliers: true,
      maxUnitsPerReceipt: 3,
      spendLadderMode: 'consuming',
    ));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ChooseGiftScreen(
            totalChances: rounds.length,
            isDemo: false,
            prizes: rounds.first.prizeNames,
            roundPrizeNames: [for (final round in rounds) round.prizeNames],
            roundGiftIds: [for (final round in rounds) round.giftIds],
            roundUnitValues: [for (final round in rounds) round.unitValues],
            roundTierMinSpends: [for (final round in rounds) round.tierMinSpend],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('شريحة 500'), findsWidgets);
    expect(find.text('قسيمة شراء 150 جنيه'), findsOneWidget);
    expect(find.textContaining('شريحة 350: قسيمة شراء 100 جنيه'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
