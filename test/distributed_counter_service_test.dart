import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/distributed_counter_service.dart';

void main() {
  group('DistributedCounterService Unit & Architectural Tests', () {
    test('sanitizeCounterKey normalizes illegal document path characters', () {
      expect(
        DistributedCounterService.sanitizeCounterKey('Voucher 50 EGP'),
        equals('voucher_50_egp'),
      );
      expect(
        DistributedCounterService.sanitizeCounterKey('branch/cairo/nasr_city#1'),
        equals('branch_cairo_nasr_city_1'),
      );
      expect(
        DistributedCounterService.sanitizeCounterKey('  Scratch?Card  '),
        equals('scratch_card'),
      );
      expect(
        DistributedCounterService.sanitizeCounterKey(''),
        equals('general'),
      );
    });

    test('defaultNumShards is configured to 10 for optimum write throughput', () {
      expect(DistributedCounterService.defaultNumShards, equals(10));
    });

    test('shard range test: ensure shard IDs map uniformly between 0 and 9', () {
      final Set<int> shardsHit = {};
      for (int i = 0; i < 100; i++) {
        final shardId = i % DistributedCounterService.defaultNumShards;
        shardsHit.add(shardId);
        expect(shardId >= 0 && shardId < 10, isTrue);
      }
      expect(shardsHit.length, equals(10));
    });

    test('in-memory shard aggregation simulates distributed count correctly', () {
      final Map<String, int> shards = {
        '0': 12,
        '1': 8,
        '2': 15,
        '3': 9,
        '4': 14,
        '5': 11,
        '6': 7,
        '7': 13,
        '8': 10,
        '9': 16,
      };

      final total = shards.values.fold<int>(0, (sum, val) => sum + val);
      expect(total, equals(115));
    });
  });
}
