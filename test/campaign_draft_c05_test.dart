import 'package:al_mraay/features/admin/domain/campaign_activation_review.dart';
import 'package:al_mraay/features/admin/domain/campaign_draft.dart';
import 'package:al_mraay/features/admin/domain/campaign_dry_run.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel _campaign({
  String id = '',
  double minimumSpend = 200,
  List<String> products = const ['كادبري'],
  List<PromotionalRuleItem> rules = const [],
  List<AllocatedPrize>? prizes,
  DateTime? start,
  DateTime? end,
  bool isAllBranches = true,
  List<String> branchIds = const [],
  List<String> branchNames = const [],
  bool whatsapp = false,
  String prompt = 'prompt',
  bool isActive = true,
}) =>
    EventModel(
      id: id,
      eventName: 'Cadbury Nov',
      targetCompany: 'Cadbury',
      companySlug: 'cadbury',
      minimumSpend: minimumSpend,
      requiredProducts: products,
      customPrompt: prompt,
      welcomeTitle: '',
      welcomeMessage: '',
      termsAndConditions: '',
      startDate: start ?? DateTime(2026, 11, 20),
      endDate: end ?? DateTime(2026, 11, 30),
      isActive: isActive,
      promotionalRules: rules,
      allocatedPrizes: prizes ??
          [
            AllocatedPrize(giftId: 'g1', name: 'فواتشر 50', allocatedQuantity: 10, remainingQuantity: 10, branchId: 'b1', branchName: 'فرع المعادي'),
          ],
      isAllBranches: isAllBranches,
      branchIds: branchIds,
      branchNames: branchNames,
      enableWhatsAppWinnerNotification: whatsapp,
      customAgencyUsername: 'ops_x',
      customAgencyPassword: 'not-for-the-server',
    );

final _now = DateTime(2026, 11, 25, 12);

void main() {
  group('C-05 draft payload', () {
    test('a new-campaign draft stores the form and no source campaign', () {
      final p = CampaignDraft.payload(event: _campaign(), updatedBy: 'admin-1');
      expect(p['sourceEventId'], isNull);
      expect(p['base'], isNull);
      expect(p['eventName'], 'Cadbury Nov');
      expect(p['companySlug'], 'cadbury');
      expect((p['event'] as Map).containsKey('createdAt'), isFalse);
      expect(p['updatedAt'], isA<FieldValue>());
    });

    test('an edit draft keeps the opened campaign as its base, round-trips through fromMap', () {
      final opened = _campaign(id: 'E1', minimumSpend: 100);
      final edited = _campaign(id: 'E1', minimumSpend: 250);
      final p = CampaignDraft.payload(event: edited, updatedBy: 'admin-1', editing: opened);
      expect(p['sourceEventId'], 'E1');
      final stored = Map<String, dynamic>.from(p)..['updatedAt'] = Timestamp.fromDate(_now);
      final d = CampaignDraft.fromMap('D1', stored);
      expect(d.isEditDraft, isTrue);
      expect(d.event.id, 'E1');
      expect(d.event.minimumSpend, 250);
      expect(d.baseEvent!.minimumSpend, 100);
      expect(d.event.startDate, DateTime(2026, 11, 20));
      expect(d.event.allocatedPrizes.single.branchName, 'فرع المعادي');
      expect(d.updatedAt, _now);
    });

    test('a draft never goes to the events collection', () {
      expect(kEventDraftsCollection, 'event_drafts');
      expect(kEventDraftsCollection, isNot('events'));
    });
  });

  group('C-05 activation review', () {
    test('a complete campaign has no danger warnings and groups stock by branch', () {
      final r = CampaignActivationReview.of(_campaign(), isNew: true, now: _now);
      expect(r.hasDanger, isFalse);
      expect(r.stockByBranch.keys, ['فرع المعادي']);
      expect(r.totalAllocated, 10);
    });

    test('missing dates on an active campaign is a danger warning', () {
      final e = EventModel.fromFirestoreMap('', {..._campaign().toFirestore()..remove('createdAt'), 'endDate': null});
      final r = CampaignActivationReview.of(e, isNew: true, now: _now);
      expect(r.hasDanger, isTrue);
      expect(r.warnings.first.message, contains('آخر يوم في الحملة'));
    });

    test('no conditions and ended campaign are flagged; no stock is not (TAG-45)', () {
      final r = CampaignActivationReview.of(
        _campaign(minimumSpend: 0, products: const [], prizes: [], end: DateTime(2026, 11, 22)),
        isNew: true,
        now: _now,
      );
      final text = r.warnings.map((w) => w.message).join('\n');
      expect(text, contains('مفيش أي شرط'));
      expect(text, isNot(contains('مفيش رصيد هدايا')));
      expect(text, contains('فات'));
      expect(r.warnings.first.level, ReviewLevel.danger);
    });

    test('a selected branch without stock and a sold-out row are not flagged (TAG-45)', () {
      final r = CampaignActivationReview.of(
        _campaign(
          isAllBranches: false,
          branchIds: const ['b1', 'b2'],
          branchNames: const ['فرع المعادي', 'فرع الدقي'],
          prizes: [
            AllocatedPrize(giftId: 'g1', name: 'فواتشر 50', allocatedQuantity: 10, remainingQuantity: 0, branchId: 'b1', branchName: 'فرع المعادي'),
          ],
        ),
        isNew: false,
        now: _now,
      );
      final text = r.warnings.map((w) => w.message).join('\n');
      expect(text, isNot(contains('فرع الدقي')));
      expect(text, isNot(contains('خلص')));
    });

    test('a spend rule with zero minimum and no product scope is flagged; WhatsApp is info', () {
      final r = CampaignActivationReview.of(
        _campaign(whatsapp: true, rules: [PromotionalRuleItem(id: 'r1', ruleTitle: 'شريحة', triggerProduct: '', minQuantity: 0, conditionType: 'by_spend', minSpend: 0, rewardValue: 'فواتشر')]),
        isNew: true,
        now: _now,
      );
      final text = r.warnings.map((w) => w.message).join('\n');
      expect(text, contains('حدها الأدنى للشراء صفر'));
      expect(text, contains('مش مربوطة بأي منتج'));
      expect(r.warnings.any((w) => w.level == ReviewLevel.info && w.message.contains('واتساب')), isTrue);
    });
  });

  group('C-05 dry-run payload', () {
    test('dates become epoch ms, credentials and prompts are not sent', () {
      final m = CampaignDryRun.campaignPayload(_campaign());
      expect(m['startDate'], DateTime(2026, 11, 20).millisecondsSinceEpoch);
      expect(m['minimumSpend'], 200);
      expect(m.containsKey('customAgencyPassword'), isFalse);
      expect(m.containsKey('customAgencyUsername'), isFalse);
      expect(m.containsKey('customPrompt'), isFalse);
      expect(m.containsKey('createdAt'), isFalse);
      bool hasFirestoreType(dynamic v) =>
          v is Timestamp || v is FieldValue || (v is Map && v.values.any(hasFirestoreType)) || (v is List && v.any(hasFirestoreType));
      expect(hasFirestoreType(m), isFalse);
    });

    test('manual receipt drops empty lines; a receipt id wins over manual lines', () {
      final receipt = CampaignDryRun.receiptPayload(receiptDate: ' 24/11/2026 ', lines: const [
        DryRunLine(name: 'كادبري', price: 120, quantity: 2),
        DryRunLine(name: '  ', price: 5),
      ]);
      expect(receipt['receipt_date'], '24/11/2026');
      expect((receipt['extracted_products'] as List).single, {'name': 'كادبري', 'price': 120.0, 'quantity': 2, 'isTargetCompany': true});
      final byId = CampaignDryRun.request(campaign: _campaign(), receipt: receipt, receiptId: ' R1 ');
      expect(byId['receiptId'], 'R1');
      expect(byId.containsKey('receipt'), isFalse);
      final manual = CampaignDryRun.request(campaign: _campaign(), receipt: receipt);
      expect(manual['receipt'], receipt);
    });

    test('result parsing', () {
      final ok = DryRunResult.fromMap({'ok': true, 'serverUnits': 2, 'mode': 'exclusive', 'campaignActive': false});
      expect(ok.ok, isTrue);
      expect(ok.serverUnits, 2);
      final bad = DryRunResult.fromMap({'ok': false, 'code': 'min_spend_not_met', 'message': 'الحد الأدنى'});
      expect(bad.ok, isFalse);
      expect(bad.code, 'min_spend_not_met');
    });
  });
}
