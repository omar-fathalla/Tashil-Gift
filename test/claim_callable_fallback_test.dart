import 'package:al_mraay/core/services/claim_callable_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('security and business callable errors do not write stock locally', () {
    const blocked = [
      'failed-precondition',
      'permission-denied',
      'unauthenticated',
      'invalid-argument',
      'deadline-exceeded',
    ];
    for (final code in blocked) {
      expect(
        staffCallableMayUseLocalStock(
          code: code,
          message: 'rejected',
          emulator: true,
        ),
        isFalse,
        reason: code,
      );
    }
    expect(
      staffCallableMayUseLocalStock(
        code: 'not-found',
        message: 'Campaign not found.',
        emulator: true,
      ),
      isFalse,
    );
    expect(
      staffCallableMayUseLocalStock(
        code: 'internal',
        message: 'internal',
        emulator: true,
      ),
      isFalse,
    );
  });

  test('only an unreachable function may fall back, including the emulator', () {
    expect(
      staffCallableMayUseLocalStock(
        code: 'unavailable',
        message: 'Connection refused',
        emulator: true,
      ),
      isTrue,
    );
    expect(
      staffCallableMayUseLocalStock(
        code: 'not-found',
        message: 'Function not found',
        emulator: false,
      ),
      isTrue,
    );
    expect(
      staffCallableMayUseLocalStock(
        code: 'unknown',
        message: 'ClientException: Connection refused',
        emulator: true,
      ),
      isTrue,
    );
    expect(
      staffCallableMayUseLocalStock(
        code: 'unknown',
        message: 'ClientException: Connection refused',
        emulator: false,
      ),
      isFalse,
    );
  });
}
