import 'dart:async';

import 'package:al_mraay/core/services/ai_model_config_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaults = AiModelConfig();

  test('errored config stream yields default config, no error', () async {
    final src = Stream<AiModelConfig>.error(Exception('[cloud_firestore/permission-denied]'));
    final events = await safeAiConfigStream(src).toList();
    expect(events.length, 1);
    expect(events.single.effectivePrimaryModel, defaults.effectivePrimaryModel);
  });

  test('anonymous user never subscribes to system_settings', () async {
    var subscribed = false;
    final events = await aiConfigStreamForUser(
      signedIn: true,
      isAnonymous: true,
      source: () {
        subscribed = true;
        return const Stream<AiModelConfig>.empty();
      },
    ).toList();
    expect(subscribed, isFalse);
    expect(events.single.effectivePrimaryModel, defaults.effectivePrimaryModel);
  });

  test('second read after the stream errors does not throw (valueOrNull)', () async {
    final container = ProviderContainer(overrides: [
      aiModelConfigStreamProvider.overrideWith(
        (ref) => safeAiConfigStream(Stream<AiModelConfig>.error(Exception('permission-denied'))),
      ),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(aiModelConfigStreamProvider, (a, b) {});
    expect(container.read(aiModelConfigStreamProvider).valueOrNull, isNull); // first scan: loading
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final v = container.read(aiModelConfigStreamProvider);
    expect(v.hasError, isFalse);
    expect(() => v.valueOrNull, returnsNormally);
    sub.close();
  });

  test('raw errored provider: valueOrNull never rethrows', () async {
    final container = ProviderContainer(overrides: [
      aiModelConfigStreamProvider.overrideWith(
        (ref) => Stream<AiModelConfig>.error(Exception('permission-denied')),
      ),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(aiModelConfigStreamProvider, (a, b) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(aiModelConfigStreamProvider).hasError, isTrue);
    expect(container.read(aiModelConfigStreamProvider).valueOrNull, isNull);
    sub.close();
  });
}
