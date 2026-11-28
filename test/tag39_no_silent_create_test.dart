import 'dart:io';

import 'package:al_mraay/features/admin/domain/campaign_save_confirmation.dart';
import 'package:flutter_test/flutter_test.dart';

// TAG-39 (C-02): no step of creating/saving a campaign swallows its error.
void main() {
  final screen = File('lib/features/admin/presentation/create_event_screen.dart').readAsStringSync();

  test('the campaign editor has no empty catch', () {
    expect(RegExp(r'catch \(\w+\) \{\s*\}').hasMatch(screen), isFalse);
  });

  test('a failed gifts sync after save is told to the admin', () {
    final finish = screen.substring(screen.indexOf('Future<void> _finishConfirmedSave('));
    final body = finish.substring(0, finish.indexOf('_showCampaignSuccessLinksDialog'));
    expect(body.contains('final synced = await'), isTrue);
    expect(body.contains('CampaignSaveTexts.giftsSyncFailed'), isTrue);
    expect(CampaignSaveTexts.giftsSyncFailed, contains('الحملة اتحفظت'));

    final service = File('lib/core/services/company_gifts_service.dart').readAsStringSync();
    expect(service.contains('Future<bool> syncCompanyGiftsAvailableQuantities('), isTrue);
  });
}
