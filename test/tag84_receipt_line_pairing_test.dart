// TAG-84: receipt 36/13/418/271126 (Gomla Market, store 418) prints each
// product name on its own line ABOVE its numbers line. The AI paired
// "كنور تتبيلة البطاطس" with the 18 EGP line above it (6223000470015, an Isis
// tea) instead of 130 EGP / 6221155141507, so the Knorr receipt was rejected
// as below minimum, and the wrong pairing was auto-added to the catalog.
import 'dart:io';

import 'package:al_mraay/core/services/ai_product_discovery_service.dart';
import 'package:al_mraay/core/services/ai_receipt_service.dart';
import 'package:al_mraay/core/utils/barcode_prefix_profile.dart';
import 'package:al_mraay/core/utils/receipt_scan_checks.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _codes(String prefix, int n) =>
    [for (var i = 0; i < n; i++) '$prefix${(100000 + i).toString()}'];

void main() {
  group('prompt: name above numbers line', () {
    const rule = AiReceiptService.posLinePairingRule;

    test('rule tells the model to pair each name with the numbers line below it', () {
      expect(rule, contains('TAG-84'));
      expect(rule, contains('فوق'));
      expect(rule, contains('تحته مباشرة'));
      expect(rule, contains('جملة ماركت'));
      expect(rule, contains('[القيمة] [السعر] [الكمية] [الباركود]'));
    });

    test('rule uses weighed items as the consistency check', () {
      expect(rule, contains('السعر × الكمية = القيمة'));
      expect(rule, contains('390.00 × 0.250 = 97.50'));
    });

    test('rule carries the 36/13/418 example with the right Knorr line', () {
      expect(rule, contains('6221155141507'));
      expect(rule, contains('130'));
      expect(rule, contains('ايزيس ليمون 12 فتلة'));
    });

    test('withPosLinePairingRule appends once', () {
      final once = AiReceiptService.withPosLinePairingRule('PROMPT');
      expect(once, startsWith('PROMPT'));
      expect(once, endsWith(rule));
      expect(AiReceiptService.withPosLinePairingRule(once), once);
    });

    test('every receipt prompt (custom and default) gets the rule before the model call', () {
      final src = File('lib/core/services/ai_receipt_service.dart').readAsStringSync();
      final apply = src.indexOf('finalPromptText = AiReceiptService.withPosLinePairingRule(finalPromptText);');
      final call = src.indexOf('final prompt = TextPart(finalPromptText);');
      expect(apply, greaterThan(0));
      expect(call, greaterThan(apply));
      expect('TextPart('.allMatches(src).length, 1, reason: 'one prompt build point');
      // The old AIR-26 wording said the name is always on the numbers line.
      expect(src, isNot(contains('على نفس السطر الأفقي للصنف تماماً')));
    });

    test('price re-read prompt allows the name-above layout', () {
      final p = ReceiptPriceSanity.reReadPrompt(const [PriceSanityFlag('كنور', 18, 130, 'name')]);
      expect(p, contains('نفس السطر'));
      expect(p, contains('تحت الاسم مباشرة'));
    });
  });

  group('BarcodePrefixProfile', () {
    final catalog = [
      ..._codes('6221155', 30),
      ..._codes('6221048', 10),
      '6223000470015', // the one bad auto-added entry must not whitelist 6223000
      '6223000999990',
    ];
    final profile = BarcodePrefixProfile.fromBarcodes(catalog);

    test('foreign prefix on a target line is a conflict', () {
      expect(profile.isActive, isTrue);
      expect(profile.conflicts('6223000111111'), isTrue);
    });

    test('known company prefixes are not conflicts', () {
      expect(profile.conflicts('6221155141507'), isFalse);
      expect(profile.conflicts('6221048000001'), isFalse);
    });

    test('exact catalog barcode is never a conflict', () {
      expect(profile.conflicts('6223000470015'), isFalse);
    });

    test('weighed, empty or invalid barcodes are not judged', () {
      expect(profile.conflicts('2303005000005'), isFalse);
      expect(profile.conflicts(''), isFalse);
      expect(profile.conflicts('12345'), isFalse);
    });

    test('Arabic digits are normalised', () {
      expect(profile.conflicts('٦٢٢١١٥٥١٤١٥٠٧'), isFalse);
      expect(profile.conflicts('٦٢٢٣٠٠٠١١١١١١'), isTrue);
    });

    test('thin catalog never flags', () {
      final thin = BarcodePrefixProfile.fromBarcodes(_codes('6221155', 5));
      expect(thin.isActive, isFalse);
      expect(thin.conflicts('6223000111111'), isFalse);
    });
  });

  group('catalog auto-add (AIR-28) guard', () {
    bool can({bool accepted = true, bool conflict = false, String bc = '6221155141507', double price = 130}) =>
        DiscoveryCriteriaEvaluator.canAutoInjectToCatalog(
          barcode: bc,
          isProbableCompanyProduct: true,
          price: price,
          receiptAccepted: accepted,
          barcodePrefixConflict: conflict,
        );

    test('accepted receipt with a consistent barcode is still auto-added', () {
      expect(can(), isTrue);
    });

    test('rejected receipt is never auto-added', () {
      expect(can(accepted: false), isFalse);
    });

    test('foreign-prefix barcode is never auto-added', () {
      expect(can(conflict: true), isFalse);
    });

    test('existing sanity limits kept', () {
      expect(can(bc: '1234567'), isFalse);
      expect(can(price: 0), isFalse);
      expect(can(price: 5000), isFalse);
    });
  });
}
