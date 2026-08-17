import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/game_audio_service.dart';
import '../localization/app_strings.dart';

/// Reusable M3 Sound Toggle Icon Button for Game AppBars & Toolbars.
class GameSoundToggleButton extends ConsumerWidget {
  final Color? color;
  final bool showSettingsOnLongPress;

  const GameSoundToggleButton({
    super.key,
    this.color,
    this.showSettingsOnLongPress = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSoundEnabled = ref.watch(soundEnabledProvider);
    final strings = AppStrings.of(ref);
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(
        isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
      tooltip: isSoundEnabled ? strings.soundEnabled : strings.soundMuted,
      onPressed: () {
        ref.read(soundEnabledProvider.notifier).state = !isSoundEnabled;
        if (!isSoundEnabled) {
          ref.read(gameAudioServiceProvider).playButtonPop();
        }
      },
      onLongPress: showSettingsOnLongPress
          ? () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => const GameSoundSettingsBottomSheet(),
              )
          : null,
    );
  }
}

/// Material 3 Bottom Sheet for Audio & Sound Effects Customization.
class GameSoundSettingsBottomSheet extends ConsumerWidget {
  const GameSoundSettingsBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSoundEnabled = ref.watch(soundEnabledProvider);
    final volume = ref.watch(soundVolumeProvider);
    final audioService = ref.watch(gameAudioServiceProvider);
    final strings = AppStrings.of(ref);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.music_note_rounded, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.gameSoundSettings,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Google & Material 3 Audio Engine',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Enable/Mute Switch Tile
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: isSoundEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    strings.soundEffects,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Switch(
                  value: isSoundEnabled,
                  onChanged: (val) {
                    ref.read(soundEnabledProvider.notifier).state = val;
                    if (val) audioService.playButtonPop();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Volume Slider
          if (isSoundEnabled) ...[
            Text(
              '${strings.volumeLevel}: ${(volume * 100).toInt()}%',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: volume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(volume * 100).toInt()}%',
              onChanged: (newVol) {
                ref.read(soundVolumeProvider.notifier).state = newVol;
              },
              onChangeEnd: (_) {
                audioService.playWheelTick();
              },
            ),
            const SizedBox(height: 12),

            // Sound Preview Chips
            Text(
              strings.previewSound,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text('عجلة الحظ', style: GoogleFonts.cairo(fontSize: 12)),
                  onPressed: () => audioService.playWheelTick(),
                ),
                ActionChip(
                  avatar: const Icon(Icons.brush_rounded, size: 16),
                  label: Text('بطاقة الخدش', style: GoogleFonts.cairo(fontSize: 12)),
                  onPressed: () => audioService.playScratchReveal(),
                ),
                ActionChip(
                  avatar: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: Text('هدية فورية', style: GoogleFonts.cairo(fontSize: 12)),
                  onPressed: () => audioService.playGiftUnlock(),
                ),
                ActionChip(
                  avatar: const Icon(Icons.celebration_rounded, size: 16),
                  label: Text('احتفال الفوز', style: GoogleFonts.cairo(fontSize: 12)),
                  onPressed: () => audioService.playWinFanfare(),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
