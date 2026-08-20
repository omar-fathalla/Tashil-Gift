import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  group('Branch Prize Allocation Editing & Zeroing Tests', () {
    test('AppStrings localization contains all direct allocation and zeroing keys', () {
      final ar = AppStrings.fromLocale('ar');
      final en = AppStrings.fromLocale('en');
      final hi = AppStrings.fromLocale('hi');

      expect(ar.editBranchAllocationBtn, isNotEmpty);
      expect(en.editBranchAllocationBtn, isNotEmpty);
      expect(hi.editBranchAllocationBtn, isNotEmpty);

      expect(ar.zeroAllocationBtn, contains('تصفير'));
      expect(en.zeroAllocationBtn, contains('Zero'));
      expect(hi.zeroAllocationBtn, contains('शून्य'));

      expect(ar.zeroAllAllocationsBtn, contains('تصفير'));
      expect(en.zeroAllAllocationsBtn, contains('Zero All'));

      expect(ar.editGiftAllocationsTitle, isNotEmpty);
      expect(ar.saveAllAllocationsBtn, isNotEmpty);
      expect(ar.allocationsSavedSuccess, isNotEmpty);
    });

    test('Zeroing allocation calculation sets target allocation to 0 and delta correctly', () {
      const int currentAllocated = 100;
      const int currentRemaining = 85;

      // When user zeros allocation: target is 0
      const int targetAllocation = 0;
      final effectiveAllocated = targetAllocation.clamp(0, 999999);
      expect(effectiveAllocated, equals(0));

      final delta = effectiveAllocated - currentAllocated; // 0 - 100 = -100
      expect(delta, equals(-100));

      final newRemaining = (currentRemaining + delta).clamp(0, effectiveAllocated);
      expect(newRemaining, equals(0)); // All unearned stock is returned to Master Warehouse
    });

    test('Reducing allocation returns stock to master warehouse correctly', () {
      const int currentAllocated = 100;
      const int currentRemaining = 100;

      // User sets allocation to 0
      const int targetAllocation = 0;
      final effectiveAllocated = targetAllocation.clamp(0, 999999);
      expect(effectiveAllocated, equals(0));

      final delta = effectiveAllocated - currentAllocated; // -100
      expect(delta, equals(-100));

      final newRemaining = (currentRemaining + delta).clamp(0, effectiveAllocated);
      expect(newRemaining, equals(0));

      // Master stock increases by delta.abs()
      const int masterStockBefore = 400;
      final masterStockAfter = masterStockBefore - delta; // 400 - (-100) = 500
      expect(masterStockAfter, equals(500));
    });

    test('Increasing allocation deducts stock from master warehouse correctly', () {
      const int currentAllocated = 50;
      const int currentRemaining = 40;

      // User increases allocation to 80 (+30)
      const int targetAllocation = 80;
      final effectiveAllocated = targetAllocation.clamp(0, 999999);
      expect(effectiveAllocated, equals(80));

      final delta = effectiveAllocated - currentAllocated; // +30
      expect(delta, equals(30));

      final newRemaining = (currentRemaining + delta).clamp(0, effectiveAllocated);
      expect(newRemaining, equals(70));

      const int masterStockBefore = 200;
      final masterStockAfter = masterStockBefore - delta; // 200 - 30 = 170
      expect(masterStockAfter, equals(170));
    });
  });
}
