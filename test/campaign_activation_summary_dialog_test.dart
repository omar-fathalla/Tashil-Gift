import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/presentation/widgets/campaign_activation_summary_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  EventModel campaign({DateTime? end}) => EventModel(
        id: '',
        eventName: 'Cadbury Nov',
        targetCompany: 'Cadbury',
        companySlug: 'cadbury',
        minimumSpend: 200,
        requiredProducts: const ['كادبري'],
        customPrompt: 'p',
        startDate: DateTime(2026, 11, 20),
        endDate: end,
        allocatedPrizes: [
          AllocatedPrize(giftId: 'g1', name: 'فواتشر 50', allocatedQuantity: 10, remainingQuantity: 10, branchId: 'b1', branchName: 'فرع المعادي'),
        ],
      );

  Future<bool?> open(WidgetTester tester, CampaignActivationReview review, String button) async {
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await CampaignActivationSummaryDialog.show(context, review),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة قبل تفعيل الحملة'), findsOneWidget);
    expect(find.text('فرع المعادي'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the review and publishes on confirm', (tester) async {
    final review = CampaignActivationReview.of(campaign(end: DateTime(2026, 11, 30)), isNew: true, now: DateTime(2026, 11, 25));
    expect(await open(tester, review, 'تأكيد وتفعيل الحملة'), isTrue);
  });

  testWidgets('a danger warning changes the publish button; going back does not publish', (tester) async {
    final review = CampaignActivationReview.of(campaign(), isNew: true, now: DateTime(2026, 11, 25));
    expect(review.hasDanger, isTrue);
    expect(await open(tester, review, 'رجوع للتعديل'), isFalse);
  });
}
