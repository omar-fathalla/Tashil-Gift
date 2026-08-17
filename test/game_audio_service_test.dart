import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:al_mraay/core/services/game_audio_service.dart';
import 'package:al_mraay/core/services/game_audio_data.dart';
import 'package:al_mraay/core/widgets/game_sound_controls.dart';
import 'package:al_mraay/core/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Game Audio Service & Sound System Tests', () {
    test('soundEnabledProvider defaults to true and toggles accurately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(soundEnabledProvider), isTrue);

      container.read(soundEnabledProvider.notifier).state = false;
      expect(container.read(soundEnabledProvider), isFalse);

      container.read(soundEnabledProvider.notifier).state = true;
      expect(container.read(soundEnabledProvider), isTrue);
    });

    test('soundVolumeProvider defaults to 0.85 and updates correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(soundVolumeProvider), closeTo(0.85, 0.001));

      container.read(soundVolumeProvider.notifier).state = 0.5;
      expect(container.read(soundVolumeProvider), closeTo(0.5, 0.001));

      container.read(soundVolumeProvider.notifier).state = 1.0;
      expect(container.read(soundVolumeProvider), closeTo(1.0, 0.001));
    });

    test('GameAudioService can be instantiated and methods invoked without throwing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final audioService = container.read(gameAudioServiceProvider);
      expect(audioService, isNotNull);

      // Disable sound to test non-playing branch
      container.read(soundEnabledProvider.notifier).state = false;
      await expectLater(audioService.playWheelTick(), completes);
      await expectLater(audioService.playWinFanfare(), completes);
      await expectLater(audioService.playScratchReveal(), completes);
      await expectLater(audioService.playGiftUnlock(), completes);
      await expectLater(audioService.playButtonPop(), completes);
      await expectLater(audioService.playCountdown(), completes);
    });

    test('All required WAV audio assets exist and have valid RIFF WAVE headers', () {
      final assetFiles = [
        'assets/audio/wheel_tick.wav',
        'assets/audio/win_fanfare.wav',
        'assets/audio/scratch_reveal.wav',
        'assets/audio/gift_unlock.wav',
        'assets/audio/button_pop.wav',
        'assets/audio/countdown.wav',
      ];

      for (final path in assetFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'File $path must exist');
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(44), reason: 'File $path must have header + data');

        // Check RIFF header
        final riff = String.fromCharCodes(bytes.sublist(0, 4));
        expect(riff, equals('RIFF'));

        // Check WAVE subchunk
        final wave = String.fromCharCodes(bytes.sublist(8, 12));
        expect(wave, equals('WAVE'));

        // Check fmt subchunk
        final fmt = String.fromCharCodes(bytes.sublist(12, 16));
        expect(fmt, equals('fmt '));
      }
    });

    test('AppStrings contains sound effects keys across Arabic, English, and Hindi', () {
      final arStrings = AppStrings('ar');
      final enStrings = AppStrings('en');
      final hiStrings = AppStrings('hi');

      expect(arStrings.soundEffects, equals('المؤثرات الصوتية'));
      expect(enStrings.soundEffects, equals('Sound Effects'));
      expect(hiStrings.soundEffects, isNotEmpty);

      expect(arStrings.soundEnabled, equals('الأصوات مفعلة'));
      expect(enStrings.soundEnabled, equals('Sound On'));

      expect(arStrings.soundMuted, equals('كتم الأصوات'));
      expect(enStrings.soundMuted, equals('Mute Sound'));

      expect(arStrings.gameSoundSettings, equals('إعدادات صوتيات الألعاب'));
      expect(enStrings.gameSoundSettings, equals('Game Audio Settings'));
    });

    testWidgets('GameSoundToggleButton renders and responds to tap', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GameSoundToggleButton(),
            ),
          ),
        ),
      );

      expect(find.byType(GameSoundToggleButton), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

      // Tap to toggle off
      await tester.tap(find.byType(GameSoundToggleButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('GameSoundSettingsBottomSheet renders controls properly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GameSoundSettingsBottomSheet(),
            ),
          ),
        ),
      );

      expect(find.byType(GameSoundSettingsBottomSheet), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('عجلة الحظ'), findsOneWidget);
      expect(find.text('بطاقة الخدش'), findsOneWidget);
      expect(find.text('هدية فورية'), findsOneWidget);
      expect(find.text('احتفال الفوز'), findsOneWidget);
    });

    test('GameAudioData contains valid base64 and decodes valid WAV headers', () {
      final effectsData = [
        GameAudioData.wheelTickBytes,
        GameAudioData.winFanfareBytes,
        GameAudioData.scratchRevealBytes,
        GameAudioData.giftUnlockBytes,
        GameAudioData.buttonPopBytes,
        GameAudioData.countdownBytes,
      ];

      for (final bytes in effectsData) {
        expect(bytes.length, greaterThan(44));
        final riff = String.fromCharCodes(bytes.sublist(0, 4));
        expect(riff, equals('RIFF'));
        final wave = String.fromCharCodes(bytes.sublist(8, 12));
        expect(wave, equals('WAVE'));
      }
    });
  });
}
