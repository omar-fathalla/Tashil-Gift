import 'package:al_mraay/core/services/company_gifts_service.dart';
import 'package:al_mraay/core/utils/canonical_branch_resolver.dart';
import 'package:al_mraay/features/games/presentation/emulator_fixture_gift_claim_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shortName = 'فرع طنطا (الغربية)';
  const outletName = 'فرع طنطا اوت ليت (الغربية)';
  const ids = ['fathalla_231', 'fathalla_243'];
  const names = [shortName, outletName];

  final prizes = [
    {
      'giftId': EmulatorFixtureGiftClaimScreen.outletGiftId,
      'name': EmulatorFixtureGiftClaimScreen.outletGiftName,
      'branchId': EmulatorFixtureGiftClaimScreen.branchId,
      'branchName': outletName,
      'remainingQuantity': 7,
      'allocatedQuantity': 7,
      'giftType': 'product',
      'unitValue': 0,
    },
    {
      'giftId': EmulatorFixtureGiftClaimScreen.shortGiftId,
      'name': 'هدية طنطا القصيرة',
      'branchId': 'fathalla_231',
      'branchName': shortName,
      'remainingQuantity': 3,
      'allocatedQuantity': 3,
      'giftType': 'product',
      'unitValue': 0,
    },
  ];

  int match(String prize, String? branchId) {
    return CompanyGiftsService.findBestPrizeMatchIndex(
      prizes,
      prize,
      branchId: branchId,
    );
  }

  test('store 243 selects the outlet gift and leaves the short gift alone', () {
    final index = match(
      EmulatorFixtureGiftClaimScreen.outletGiftId,
      EmulatorFixtureGiftClaimScreen.branchId,
    );
    expect(index, 0);
    expect(prizes[index]['remainingQuantity'], 7);
    expect(prizes[1]['remainingQuantity'], 3);
    expect(prizes[index]['branchId'], 'fathalla_243');
  });

  test('the short branch id selects only the short gift', () {
    final index = match(EmulatorFixtureGiftClaimScreen.shortGiftId, 'fathalla_231');
    expect(index, 1);
    expect(prizes[index]['branchId'], 'fathalla_231');
  });

  test('sibling, unknown, partial, and foreign ids do not select a gift', () {
    expect(
      match(EmulatorFixtureGiftClaimScreen.outletGiftId, 'fathalla_231'),
      -1,
    );
    expect(match(EmulatorFixtureGiftClaimScreen.outletGiftName, 'طنطا اوت'), -1);
    expect(match(EmulatorFixtureGiftClaimScreen.outletGiftName, '999'), -1);
    expect(match(EmulatorFixtureGiftClaimScreen.outletGiftName, 'gomla_418'), -1);
    expect(match('هدية طنطا القصيرة', 'fathalla_243'), -1);
  });

  test('a shared gift name still follows the branch id', () {
    final shared = [
      {
        'giftId': 'shared-243',
        'name': 'هدية مشتركة',
        'branchId': 'fathalla_243',
        'branchName': outletName,
        'remainingQuantity': 7,
        'giftType': 'product',
      },
      {
        'giftId': 'shared-231',
        'name': 'هدية مشتركة',
        'branchId': 'fathalla_231',
        'branchName': shortName,
        'remainingQuantity': 3,
        'giftType': 'product',
      },
    ];
    expect(
      CompanyGiftsService.findBestPrizeMatchIndex(
        shared,
        'هدية مشتركة',
        branchId: 'fathalla_243',
      ),
      0,
    );
    expect(
      CompanyGiftsService.findBestPrizeMatchIndex(
        shared,
        'هدية مشتركة',
        branchId: 'طنطا اوت',
      ),
      -1,
    );
  });

  test('gomla_418 stays stored and is not rewritten from receipt 243', () {
    final match = CanonicalBranchResolver.resolve(
      branchIds: ids,
      branchNames: names,
      branchId: 'gomla_418',
      detectedName: shortName,
      receiptNumber: '137/4/243/061126',
    );
    expect(match.certain, isFalse);
    expect(match.id, 'gomla_418');
    expect(match.name, shortName);
    expect(
      CompanyGiftsService.findBestPrizeMatchIndex(
        prizes,
        EmulatorFixtureGiftClaimScreen.outletGiftName,
        branchId: match.id,
      ),
      -1,
    );
  });
}
