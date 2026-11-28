import 'package:al_mraay/core/utils/barcode_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TAG-86 barcode prefix matching', () {
    test('9-digit Knorr catalog code does not swallow a Dove barcode', () {
      expect(barcodesMatch('6221155101204', '622115510'), isFalse);
    });
    test('exact match', () {
      expect(barcodesMatch('6221155146656', '6221155146656'), isTrue);
    });
    test('12/13-digit POS variation still matches both ways', () {
      expect(barcodesMatch('622300066001', '6223000660010'), isTrue);
      expect(barcodesMatch('6223000660010', '622300066001'), isTrue);
    });
    test('11-digit or two-digit differences do not match', () {
      expect(barcodePrefixVariant('62211551012', '6221155101204'), isFalse);
      expect(barcodePrefixVariant('62211551', '6221155101204'), isFalse);
    });
  });
}
