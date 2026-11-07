import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/services/multi_campaign_receipt_evaluator.dart';
import 'package:al_mraay/core/utils/receipt_date_window.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

/// 2.0.162 (issue #2/#3): campaign window in Cairo days, end day inclusive.
/// Panda: start Oct 25 00:00 Cairo, end stored Nov 3 00:00 Cairo.
void main() {
  // Oct 25 is still summer time (UTC+3); Nov 3 is winter time (UTC+2).
  final start = DateTime.utc(2026, 10, 24, 21);
  final end = DateTime.utc(2026, 11, 2, 22);

  EventModel panda() => EventModel(
        id: 'panda',
        eventName: 'حمله منتجات شركه باندا',
        targetCompany: 'باندا',
        minimumSpend: 0,
        startDate: start,
        endDate: end,
      );

  tearDown(() => campaignClock = DateTime.now);

  group('Cairo offsets', () {
    test('summer and winter time', () {
      expect(cairoUtcOffsetHours(DateTime.utc(2026, 7, 1)), 3);
      expect(cairoUtcOffsetHours(DateTime.utc(2026, 12, 1)), 2);
      expect(cairoStartOfDay(2026, 10, 25), DateTime.utc(2026, 10, 24, 21));
      expect(cairoStartOfDay(2026, 11, 4), DateTime.utc(2026, 11, 3, 22));
    });
    test('first and last day are read in Cairo', () {
      expect(campaignFirstDay(start), DateTime(2026, 10, 25));
      expect(campaignLastDay(end), DateTime(2026, 11, 3));
      expect(campaignLastDayLabel(end), '3/11/2026');
    });
  });

  group('Panda receipt dates', () {
    final cases = {
      '2026/10/24': false,
      '2026/10/25': true,
      '2026/11/02': true,
      '2026/11/03': true,
      '2026/11/04': false,
      '24/10/2026': false,
      '25/10/2026': true,
      '30/10/2026': true,
    };
    cases.forEach((date, ok) {
      test('$date -> ${ok ? "accept" : "reject"}', () {
        expect(receiptDateWithinCampaign(date, start, end), ok);
        expect(campaignReceiptDateRejection(date, start, end) == null, ok);
      });
    });
  });

  group('Panda link expiry (Cairo time)', () {
    test('open on Nov 3 23:59 Cairo, closed at Nov 4 00:00 Cairo', () {
      expect(isCampaignExpired(end, now: DateTime.utc(2026, 11, 3, 21, 59)), isFalse);
      expect(isCampaignExpired(end, now: DateTime.utc(2026, 11, 3, 22)), isTrue);
    });
    test('not started before Oct 25 00:00 Cairo', () {
      expect(isCampaignNotStarted(start, now: DateTime.utc(2026, 10, 24, 20, 59)), isTrue);
      expect(isCampaignNotStarted(start, now: DateTime.utc(2026, 10, 24, 21)), isFalse);
    });
    test('EventModel getters use the same window', () {
      campaignClock = () => DateTime.utc(2026, 11, 3, 21, 59);
      expect(panda().isExpired, isFalse);
      expect(panda().canPromoterAccess, isTrue);
      campaignClock = () => DateTime.utc(2026, 11, 3, 22);
      expect(panda().isExpired, isTrue);
      expect(panda().canPromoterAccess, isFalse);
    });
    test('same result for instants expressed in a non-Cairo zone', () {
      // Same instants given as other-offset wall clocks (Tokyo +9, NY -5).
      final tokyoBefore = DateTime.utc(2026, 11, 3, 21, 59);
      final nyAfter = DateTime.utc(2026, 11, 3, 22, 0, 1);
      expect(isCampaignExpired(end, now: tokyoBefore.toLocal()), isFalse);
      expect(isCampaignExpired(end, now: nyAfter.toLocal()), isTrue);
      expect(campaignLastDay(end.toLocal()), DateTime(2026, 11, 3));
    });
  });

  group('multi-scan evaluator applies each campaign window', () {
    AiReceiptAnalysisResult receipt(String date) => AiReceiptAnalysisResult(
          isValid: true,
          message: 'ok',
          receiptNumber: 'R1',
          storeChainDetected: '',
          branchDetected: '',
          isBranchMatched: true,
          extractedProducts: const [],
          receiptDate: date,
          targetCompanyTotal: 100,
        );
    test('out-of-window receipt is rejected with a date reason', () {
      campaignClock = () => DateTime.utc(2026, 11, 1, 10);
      for (final d in ['2026/11/04', '2026/10/24']) {
        final r = MultiCampaignReceiptEvaluator.evaluateCampaign(
            result: receipt(d), campaign: panda());
        expect(r.isQualified, isFalse);
        expect(r.rejectionReason, contains('تاريخ الشراء'));
      }
    });
    test('in-window receipt passes the date step', () {
      campaignClock = () => DateTime.utc(2026, 11, 1, 10);
      final r = MultiCampaignReceiptEvaluator.evaluateCampaign(
          result: receipt('2026/11/03'), campaign: panda());
      expect(r.rejectionReason ?? '', isNot(contains('تاريخ الشراء')));
    });
  });

  group('issue #3: save validation', () {
    test('end before start is blocked', () {
      final msg = campaignDatesError(end, start);
      expect(msg, isNotNull);
      expect(msg, contains('لا يمكن الحفظ'));
    });
    test('same day and normal ranges are allowed', () {
      expect(campaignDatesError(start, start), isNull);
      expect(campaignDatesError(start, end), isNull);
      expect(campaignDatesError(null, end), isNull);
    });
    test('picked day stored as Cairo 00:00', () {
      expect(pickedDayToCairoInstant(DateTime(2026, 11, 3)),
          DateTime.utc(2026, 11, 2, 22));
    });
  });
}
