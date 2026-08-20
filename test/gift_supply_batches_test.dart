import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/features/admin/domain/company_gift_model.dart';

void main() {
  group('Gift Supply Batches & Movements Domain Tests', () {
    test('GiftSupplyBatch serializes and deserializes accurately with date and reference', () {
      final now = DateTime(2026, 8, 20, 10, 30);
      final batch = GiftSupplyBatch(
        id: 'batch_001',
        batchNumber: 2,
        quantity: 150,
        supplyDate: now,
        referenceNumber: 'PO-2026-894',
        notes: 'توريد دفعة صيفية إضافية من المصنع',
        addedBy: 'أحمد فؤاد - مدير المستودع',
      );

      final map = batch.toMap();
      expect(map['id'], 'batch_001');
      expect(map['batchNumber'], 2);
      expect(map['quantity'], 150);
      expect(map['referenceNumber'], 'PO-2026-894');
      expect(map['notes'], 'توريد دفعة صيفية إضافية من المصنع');
      expect(map['addedBy'], 'أحمد فؤاد - مدير المستودع');

      final fromMap = GiftSupplyBatch.fromMap(map);
      expect(fromMap.id, 'batch_001');
      expect(fromMap.batchNumber, 2);
      expect(fromMap.quantity, 150);
      expect(fromMap.supplyDate.year, 2026);
      expect(fromMap.supplyDate.month, 8);
      expect(fromMap.supplyDate.day, 20);
      expect(fromMap.referenceNumber, 'PO-2026-894');
      expect(fromMap.notes, 'توريد دفعة صيفية إضافية من المصنع');
    });

    test('CompanyGiftModel parses multiple supply batches and computes batch count', () {
      final b1 = GiftSupplyBatch(
        id: 'b1',
        batchNumber: 1,
        quantity: 100,
        supplyDate: DateTime(2026, 1, 15),
        referenceNumber: 'PO-101',
        notes: 'الدفعة الأولى التأسيسية',
      );

      final b2 = GiftSupplyBatch(
        id: 'b2',
        batchNumber: 2,
        quantity: 150,
        supplyDate: DateTime(2026, 4, 1),
        referenceNumber: 'PO-102',
        notes: 'توريد دفعة عروض رمضان',
      );

      final b3 = GiftSupplyBatch(
        id: 'b3',
        batchNumber: 3,
        quantity: 200,
        supplyDate: DateTime(2026, 8, 20),
        referenceNumber: 'PO-103',
        notes: 'توريد دفعة الصيف',
      );

      final gift = CompanyGiftModel(
        id: 'gift_unilever_01',
        companySlug: 'unilever',
        companyName: 'يونيليفر',
        giftName: 'شامبو صانسيلك 400 مل',
        totalQuantity: 450,
        availableQuantity: 320,
        batches: [b1, b2, b3],
      );

      expect(gift.batches.length, 3);
      expect(gift.batchCount, 3);
      expect(gift.totalQuantity, 450);
      expect(gift.availableQuantity, 320);
      expect(gift.batches[0].batchNumber, 1);
      expect(gift.batches[1].batchNumber, 2);
      expect(gift.batches[2].batchNumber, 3);

      final map = gift.toMap();
      final reconstructed = CompanyGiftModel.fromMap(map, 'gift_unilever_01');
      expect(reconstructed.batches.length, 3);
      expect(reconstructed.batchCount, 3);
      expect(reconstructed.batches[1].referenceNumber, 'PO-102');
    });

    test('Low stock threshold calculation alerts when available stock is depleted', () {
      final healthyGift = CompanyGiftModel(
        id: 'g1',
        companySlug: 'unilever',
        companyName: 'يونيليفر',
        giftName: 'صابون لوكس',
        totalQuantity: 100,
        availableQuantity: 40,
        lowStockThreshold: 15,
      );
      expect(healthyGift.isLowStock, false);

      final lowStockGift = CompanyGiftModel(
        id: 'g2',
        companySlug: 'unilever',
        companyName: 'يونيليفر',
        giftName: 'صابون لوكس',
        totalQuantity: 100,
        availableQuantity: 10,
        lowStockThreshold: 15,
      );
      expect(lowStockGift.isLowStock, true);
    });

    test('GiftStockMovement tracks all movement types and identifies additions vs deductions', () {
      final now = DateTime(2026, 8, 20, 12, 0);

      // 1. Supply Batch (+100)
      final mSupply = GiftStockMovement(
        id: 'm1',
        companySlug: 'unilever',
        giftId: 'gift_dove',
        giftName: 'دوف كريم 150 مل',
        movementType: 'supply_batch',
        quantityChange: 100,
        previousTotal: 200,
        newTotal: 300,
        previousAvailable: 150,
        newAvailable: 250,
        reference: 'PO-8821',
        notes: 'دفعة توريد جديدة',
        performedBy: 'أدمن النظام',
        timestamp: now,
      );
      expect(mSupply.isAddition, true);
      expect(mSupply.typeLabelAr, 'توريد دفعة جديدة');
      expect(mSupply.typeLabelEn, 'Supply Batch Inward');

      // 2. Periodic Audit Positive Adjustment (+5)
      final mAdjAdd = GiftStockMovement(
        id: 'm2',
        companySlug: 'unilever',
        giftId: 'gift_dove',
        giftName: 'دوف كريم 150 مل',
        movementType: 'adjustment_add',
        quantityChange: 5,
        previousTotal: 300,
        newTotal: 305,
        previousAvailable: 250,
        newAvailable: 255,
        reference: 'جرد دوري',
        notes: 'زيادة ناتجة عن مطابقة الجرد الفعلي للمستودع',
        performedBy: 'مراقب الجودة',
        timestamp: now,
      );
      expect(mAdjAdd.isAddition, true);
      expect(mAdjAdd.typeLabelAr, 'تسوية جردية بالزيادة');

      // 3. Damaged Goods Negative Adjustment (-3)
      final mAdjDeduct = GiftStockMovement(
        id: 'm3',
        companySlug: 'unilever',
        giftId: 'gift_dove',
        giftName: 'دوف كريم 150 مل',
        movementType: 'adjustment_deduct',
        quantityChange: -3,
        previousTotal: 305,
        newTotal: 302,
        previousAvailable: 255,
        newAvailable: 252,
        reference: 'تالف أثناء النقل',
        notes: 'عبوات مكسورة تم إتلافها بموجب محضر',
        performedBy: 'أمين المخزن',
        timestamp: now,
      );
      expect(mAdjDeduct.isAddition, false);
      expect(mAdjDeduct.typeLabelAr, 'تسوية جردية بالنقص / هالك');

      // 4. Campaign Allocation (-50 available)
      final mAlloc = GiftStockMovement(
        id: 'm4',
        companySlug: 'unilever',
        giftId: 'gift_dove',
        giftName: 'دوف كريم 150 مل',
        movementType: 'campaign_allocation',
        quantityChange: -50,
        previousTotal: 302,
        newTotal: 302,
        previousAvailable: 252,
        newAvailable: 202,
        reference: 'حملة كارفور سيتي سنتر',
        notes: 'تخصيص لفرع سموحة',
        performedBy: 'مدير الحملات',
        timestamp: now,
      );
      expect(mAlloc.isAddition, false);
      expect(mAlloc.typeLabelAr, 'تخصيص لحملة وفروع');

      // 5. Campaign Return (+10 unused returned)
      final mReturn = GiftStockMovement(
        id: 'm5',
        companySlug: 'unilever',
        giftId: 'gift_dove',
        giftName: 'دوف كريم 150 مل',
        movementType: 'campaign_return',
        quantityChange: 10,
        previousTotal: 302,
        newTotal: 302,
        previousAvailable: 202,
        newAvailable: 212,
        reference: 'مرتجع حملة كارفور',
        notes: 'إرجاع الفائض غير المصروف بعد انتهاء الفعالية',
        performedBy: 'مشرف الفرع',
        timestamp: now,
      );
      expect(mReturn.isAddition, true);
      expect(mReturn.typeLabelAr, 'استرجاع متبقي من حملة');
    });

    test('Sequential stock movements simulate complete multi-batch inventory lifecycle', () {
      int totalStock = 100;
      int availableStock = 100;
      final List<GiftStockMovement> movements = [];

      movements.add(GiftStockMovement(
        id: 'log_1',
        companySlug: 'unilever',
        giftId: 'gift_axe',
        giftName: 'مزيل عرق آكس',
        movementType: 'supply_batch',
        quantityChange: 100,
        previousTotal: 0,
        newTotal: 100,
        previousAvailable: 0,
        newAvailable: 100,
        reference: 'PO-INITIAL',
        notes: 'الدفعة الأولى',
        performedBy: 'مسؤول النظام',
        timestamp: DateTime(2026, 1, 1),
      ));

      availableStock -= 60;
      movements.add(GiftStockMovement(
        id: 'log_2',
        companySlug: 'unilever',
        giftId: 'gift_axe',
        giftName: 'مزيل عرق آكس',
        movementType: 'campaign_allocation',
        quantityChange: -60,
        previousTotal: 100,
        newTotal: 100,
        previousAvailable: 100,
        newAvailable: availableStock,
        reference: 'حملة الصيف',
        notes: 'تخصيص لفرع كارفور',
        performedBy: 'مسؤول النظام',
        timestamp: DateTime(2026, 6, 1),
      ));
      expect(totalStock, 100);
      expect(availableStock, 40);

      totalStock += 150;
      availableStock += 150;
      movements.add(GiftStockMovement(
        id: 'log_3',
        companySlug: 'unilever',
        giftId: 'gift_axe',
        giftName: 'مزيل عرق آكس',
        movementType: 'supply_batch',
        quantityChange: 150,
        previousTotal: 100,
        newTotal: totalStock,
        previousAvailable: 40,
        newAvailable: availableStock,
        reference: 'PO-2026-SUPPLY-2',
        notes: 'دفعة توريد ثانية',
        performedBy: 'مسؤول المستودع',
        timestamp: DateTime(2026, 7, 15),
      ));
      expect(totalStock, 250);
      expect(availableStock, 190);

      totalStock -= 5;
      availableStock -= 5;
      movements.add(GiftStockMovement(
        id: 'log_4',
        companySlug: 'unilever',
        giftId: 'gift_axe',
        giftName: 'مزيل عرق آكس',
        movementType: 'adjustment_deduct',
        quantityChange: -5,
        previousTotal: 250,
        newTotal: totalStock,
        previousAvailable: 190,
        newAvailable: availableStock,
        reference: 'محضر إتلاف رقم 12',
        notes: 'تالف أثناء المناولة',
        performedBy: 'أمين المخزن',
        timestamp: DateTime(2026, 8, 1),
      ));
      expect(totalStock, 245);
      expect(availableStock, 185);

      availableStock += 8;
      movements.add(GiftStockMovement(
        id: 'log_5',
        companySlug: 'unilever',
        giftId: 'gift_axe',
        giftName: 'مزيل عرق آكس',
        movementType: 'campaign_return',
        quantityChange: 8,
        previousTotal: 245,
        newTotal: totalStock,
        previousAvailable: 185,
        newAvailable: availableStock,
        reference: 'مرتجع حملة الصيف',
        notes: 'استلام فائض الهدايا غير المستلمة',
        performedBy: 'مشرف الحملة',
        timestamp: DateTime(2026, 8, 15),
      ));
      expect(totalStock, 245);
      expect(availableStock, 193);

      expect(movements.length, 5);
      expect(movements.first.newTotal, 100);
      expect(movements.last.newTotal, 245);
      expect(movements.last.newAvailable, 193);
    });
  });
}
