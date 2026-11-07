import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/utils/receipt_branch_resolver.dart';
import 'package:al_mraay/core/utils/store_code_branch_resolver.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'package:al_mraay/features/client_portal/presentation/widgets/receipt_issue_dialog.dart';

BranchModel _b(String code, String name, {String pattern = ''}) => BranchModel(
      id: 'fathalla_$code',
      retailChainId: 'fathalla',
      retailChainName: 'أسواق فتح الله',
      branchName: name,
      branchCode: code,
      receiptSignature: BranchReceiptSignature(storeId: code, receiptPattern: pattern),
    );

void main() {
  final branches = [
    _b('272', 'فرع بدر', pattern: '272/YYMMDD'),
    _b('224', 'فرع عجمي ستار', pattern: '224/YYMMDD'),
    _b('10', 'فرع عشرة', pattern: '10/YYMMDD'),
  ];

  test('Fathalla 145/10/224/301026 resolves to 224 (عجمي ستار), not Badr', () {
    final b = StoreCodeBranchResolver.resolve('145/10/224/301026', branches);
    expect(b?.id, 'fathalla_224');
    expect(b?.branchName, 'فرع عجمي ستار');
  });

  test('Arabic digits are normalized', () {
    expect(StoreCodeBranchResolver.resolve('١٤٥/١٠/٢٢٤/٣٠١٠٢٦', branches)?.id, 'fathalla_224');
  });

  test('no match keeps the AI branch (null)', () {
    expect(StoreCodeBranchResolver.resolve('145/10/999/301026', branches), isNull);
    expect(StoreCodeBranchResolver.resolve('', branches), isNull);
    expect(StoreCodeBranchResolver.resolve('INV-55', branches), isNull);
  });

  test('without a pattern, default layout is code before trailing date', () {
    final noPattern = [_b('224', 'فرع عجمي ستار'), _b('272', 'فرع بدر')];
    expect(StoreCodeBranchResolver.resolve('145/10/224/301026', noPattern)?.id, 'fathalla_224');
    expect(StoreCodeBranchResolver.resolve('145/10/224/ABC', noPattern), isNull);
  });

  test('campaign resolver: store code overrides AI branch name', () {
    final event = EventModel(
      id: 'e1',
      eventName: 'بريكي',
      targetCompany: 'نستله',
      companySlug: 'x',
      minimumSpend: 250,
      branchNames: const ['فرع بدر', 'فرع عجمي ستار'],
      branchIds: const ['fathalla_272', 'fathalla_224'],
      allocatedPrizes: const [],
      createdAt: DateTime(2026),
    );
    final r = ReceiptBranchResolver.resolve(event, 'فرع بدر', receiptNumber: '145/10/224/301026');
    expect(r.id, 'fathalla_224');
    expect(r.name, 'فرع عجمي ستار');
    final fallback = ReceiptBranchResolver.resolve(event, 'فرع بدر', receiptNumber: '145/10/999/301026');
    expect(fallback.id, 'fathalla_272');
  });

  test('prompt branch-source rule forbids footer ads', () {
    expect(AiReceiptService.branchSourceRule, contains('كود المتجر'));
    expect(AiReceiptService.branchSourceRule, contains('تم افتتاح فرع'));
  });

  test('locked receipt title', () {
    expect(receiptIssueSpecs[ReceiptIssueKind.alreadyRedeemed]!.titleAr, 'الفاتورة دي اترفعت واتقبلت قبل كده');
  });
}
