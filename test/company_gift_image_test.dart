import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';
import 'package:al_mraay/features/admin/domain/event_model.dart';

void main() {
  group('Company Gift & Prize Image Serialization Tests', () {
    test('CompanyGiftModel correctly serializes and deserializes imageUrl', () {
      final giftWithImage = CompanyGiftModel(
        id: 'gift-1',
        companySlug: 'unilever',
        companyName: 'Unilever',
        giftName: 'شامبو تريزيمي 400 مل',
        totalQuantity: 50,
        availableQuantity: 50,
        giftType: 'physical',
        unitValue: 120.0,
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/tresemme.png',
        createdAt: DateTime(2026, 9, 1),
      );

      expect(giftWithImage.imageUrl, 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/tresemme.png');

      final map = giftWithImage.toFirestore();
      expect(map['imageUrl'], 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/tresemme.png');

      final fromMapGift = CompanyGiftModel.fromMap(map, 'gift-1');
      expect(fromMapGift.imageUrl, 'https://firebasestorage.googleapis.com/v0/b/tashil-gift.appspot.com/o/tresemme.png');

      // Test copyWith imageUrl
      final updated = fromMapGift.copyWith(imageUrl: 'https://example.com/new_image.jpg');
      expect(updated.imageUrl, 'https://example.com/new_image.jpg');

      // Test null imageUrl
      final giftWithoutImage = CompanyGiftModel(
        id: 'gift-2',
        companySlug: 'unilever',
        companyName: 'Unilever',
        giftName: 'قسيمة مشتريات 50 ج.م',
        totalQuantity: 100,
        availableQuantity: 100,
        giftType: 'voucher',
        unitValue: 50.0,
        imageUrl: null,
        createdAt: DateTime(2026, 9, 1),
      );

      expect(giftWithoutImage.imageUrl, isNull);
      final map2 = giftWithoutImage.toFirestore();
      expect(map2['imageUrl'], isNull);

      final fromMapGift2 = CompanyGiftModel.fromMap(map2, 'gift-2');
      expect(fromMapGift2.imageUrl, isNull);
    });

    test('AllocatedPrize correctly serializes and deserializes imageUrl', () {
      final prize = AllocatedPrize(
        giftId: 'gift-p-1',
        name: 'سماعات بلوتوث',
        allocatedQuantity: 15,
        remainingQuantity: 12,
        imageUrl: 'https://example.com/headphones.jpg',
      );

      expect(prize.imageUrl, 'https://example.com/headphones.jpg');

      final map = prize.toMap();
      expect(map['imageUrl'], 'https://example.com/headphones.jpg');

      final deserialized = AllocatedPrize.fromMap(map);
      expect(deserialized.imageUrl, 'https://example.com/headphones.jpg');
      expect(deserialized.name, 'سماعات بلوتوث');
      expect(deserialized.allocatedQuantity, 15);

      final updatedPrize = deserialized.copyWith(imageUrl: 'https://example.com/updated.png');
      expect(updatedPrize.imageUrl, 'https://example.com/updated.png');
    });

    test('LinkedGiftAllocation correctly serializes and deserializes imageUrl', () {
      final linked = LinkedGiftAllocation(
        giftId: 'gift-123',
        giftName: 'ماكينة قهوة',
        quantity: 2,
        unitValue: 850.0,
        giftType: 'product',
        imageUrl: 'https://example.com/coffee.jpg',
      );

      expect(linked.imageUrl, 'https://example.com/coffee.jpg');

      final map = linked.toMap();
      expect(map['imageUrl'], 'https://example.com/coffee.jpg');

      final deserialized = LinkedGiftAllocation.fromMap(map);
      expect(deserialized.imageUrl, 'https://example.com/coffee.jpg');
      expect(deserialized.giftName, 'ماكينة قهوة');
      expect(deserialized.quantity, 2);

      final updatedLinked = deserialized.copyWith(imageUrl: 'https://example.com/coffee-2.jpg');
      expect(updatedLinked.imageUrl, 'https://example.com/coffee-2.jpg');
    });
  });
}
