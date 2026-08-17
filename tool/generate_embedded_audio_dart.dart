// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() {
  final root = Directory.current.path;
  final audioDir = Directory('$root/assets/audio');
  final files = {
    'wheelTick': 'wheel_tick.wav',
    'scratchReveal': 'scratch_reveal.wav',
    'giftUnlock': 'gift_unlock.wav',
    'winFanfare': 'win_fanfare.wav',
    'buttonPop': 'button_pop.wav',
    'countdown': 'countdown.wav',
  };

  final sb = StringBuffer();
  sb.writeln('// Auto-generated embedded sound assets in base64 data URLs and raw bytes.');
  sb.writeln('// Ensures 100% offline, zero-latency, freeze-proof audio playback on Web & Mobile.');
  sb.writeln("import 'dart:convert';");
  sb.writeln("import 'dart:typed_data';");
  sb.writeln('');
  sb.writeln('class GameAudioData {');

  for (final entry in files.entries) {
    final file = File('${audioDir.path}/${entry.value}');
    if (!file.existsSync()) {
      print('Missing ${file.path}');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final b64 = base64Encode(bytes);
    final varName = entry.key;

    sb.writeln("  static const String ${varName}Base64 = '$b64';");
    sb.writeln("  static const String ${varName}DataUrl = 'data:audio/wav;base64,$b64';");
    sb.writeln('  static Uint8List get ${varName}Bytes => base64Decode(${varName}Base64);');
    sb.writeln('');
  }

  sb.writeln('}');

  File('$root/lib/core/services/game_audio_data.dart')
      .writeAsStringSync(sb.toString());

  print('Successfully generated lib/core/services/game_audio_data.dart');
}
