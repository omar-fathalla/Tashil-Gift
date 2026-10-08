import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:al_mraay/core/utils/receipt_image_calibrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptImageCalibrator Unit Tests', () {
    late Uint8List sampleLargeImageBytes;

    setUp(() {
      // Create an 800x1000 synthetic test image with complex pixel variation
      final image = img.Image(width: 800, height: 1000);
      for (int y = 0; y < 1000; y++) {
        for (int x = 0; x < 800; x++) {
          final val = (x * 7 + y * 13) % 256;
          image.setPixelRgb(x, y, val, (val * 3) % 256, (val * 5) % 256);
        }
      }

      // Encode as uncompressed BMP (~2.4 MB) to simulate high-payload camera output
      sampleLargeImageBytes = Uint8List.fromList(img.encodeBmp(image));
    });

    test('successfully downscales and compresses high-resolution receipt image', () async {
      final result = await ReceiptImageCalibrator.calibrateReceiptBytes(
        sampleLargeImageBytes,
        maxWidth: 1200,
        maxHeight: 1400,
        quality: 75,
        contrast: 1.25,
      );

      expect(result.bytes, isNotEmpty);
      expect(result.width, lessThanOrEqualTo(1200));
      expect(result.height, lessThanOrEqualTo(1400));
      expect(result.originalSize, equals(sampleLargeImageBytes.lengthInBytes));
      expect(result.calibratedSize, greaterThan(0));
      expect(result.calibratedSize, lessThan(result.originalSize));
      expect(result.compressionRatio, greaterThan(40.0)); // Substantial payload reduction
      expect(result.mimeType, equals('image/jpeg'));
      expect(result.compressionRatioLabel, startsWith('-'));
    });

    test('preserves aspect ratio during downscaling', () async {
      final result = await ReceiptImageCalibrator.calibrateReceiptBytes(
        sampleLargeImageBytes,
        maxWidth: 400,
        maxHeight: 800,
      );

      // Original ratio: 800 / 1000 = 0.8
      final calibratedRatio = result.width / result.height;
      expect((calibratedRatio - 0.8).abs(), lessThan(0.05));
    });

    test('gracefully recovers when provided invalid or corrupted bytes', () async {
      final corruptedBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);

      final result = await ReceiptImageCalibrator.calibrateReceiptBytes(corruptedBytes);

      expect(result.bytes, equals(corruptedBytes));
      expect(result.originalSize, equals(corruptedBytes.lengthInBytes));
      expect(result.calibratedSize, equals(corruptedBytes.lengthInBytes));
      expect(result.width, equals(0));
      expect(result.height, equals(0));
    });

    test('calibrateBatch processes multiple images concurrently', () async {
      final batch = [sampleLargeImageBytes, sampleLargeImageBytes];
      final results = await ReceiptImageCalibrator.calibrateBatch(
        batch,
        maxWidth: 400,
        maxHeight: 500,
      );

      expect(results.length, equals(2));
      for (final r in results) {
        expect(r.bytes, isNotEmpty);
        expect(r.width, lessThanOrEqualTo(400));
        expect(r.height, lessThanOrEqualTo(500));
        expect(r.compressionRatio, greaterThan(0));
      }
    });

    test('formats size labels properly', () {
      final result = CalibratedImageResult(
        bytes: Uint8List(0),
        originalSize: 4 * 1024 * 1024, // 4 MB
        calibratedSize: 350 * 1024, // 350 KB
        width: 1200,
        height: 1500,
        duration: Duration(milliseconds: 45),
      );

      expect(result.originalSizeLabel, contains('MB'));
      expect(result.calibratedSizeLabel, contains('KB'));
      expect(result.sizeSavedKbLabel, contains('KB'));
      expect(result.compressionRatio, greaterThan(90.0));
    });
  });
}
