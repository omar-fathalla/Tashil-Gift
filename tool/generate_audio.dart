// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

Uint8List createWav(List<double> samples, {int sampleRate = 44100}) {
  final numSamples = samples.length;
  final numChannels = 1;
  final bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final blockAlign = numChannels * (bitsPerSample ~/ 8);
  final subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
  final chunkSize = 36 + subChunk2Size;

  final byteData = ByteData(44 + subChunk2Size);

  // RIFF header
  byteData.setUint8(0, 0x52); // 'R'
  byteData.setUint8(1, 0x49); // 'I'
  byteData.setUint8(2, 0x46); // 'F'
  byteData.setUint8(3, 0x46); // 'F'
  byteData.setUint32(4, chunkSize, Endian.little);
  byteData.setUint8(8, 0x57);  // 'W'
  byteData.setUint8(9, 0x41);  // 'A'
  byteData.setUint8(10, 0x56); // 'V'
  byteData.setUint8(11, 0x45); // 'E'

  // "fmt " subchunk
  byteData.setUint8(12, 0x66); // 'f'
  byteData.setUint8(13, 0x6D); // 'm'
  byteData.setUint8(14, 0x74); // 't'
  byteData.setUint8(15, 0x20); // ' '
  byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
  byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
  byteData.setUint16(22, numChannels, Endian.little);
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, byteRate, Endian.little);
  byteData.setUint16(32, blockAlign, Endian.little);
  byteData.setUint16(34, bitsPerSample, Endian.little);

  // "data" subchunk
  byteData.setUint8(36, 0x64); // 'd'
  byteData.setUint8(37, 0x61); // 'a'
  byteData.setUint8(38, 0x74); // 't'
  byteData.setUint8(39, 0x61); // 'a'
  byteData.setUint32(40, subChunk2Size, Endian.little);

  int offset = 44;
  for (int i = 0; i < numSamples; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    final intSample = (clamped * 32767).toInt();
    byteData.setInt16(offset, intSample, Endian.little);
    offset += 2;
  }

  return byteData.buffer.asUint8List();
}

List<double> generateWheelTick({int sampleRate = 44100}) {
  final duration = 0.04; // 40ms
  final numSamples = (sampleRate * duration).toInt();
  final samples = <double>[];
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = exp(-t * 120); // fast decay
    final freq = 1200.0 - (t * 8000.0);
    final s = sin(2 * pi * max(200.0, freq) * t) * 0.9 * env;
    samples.add(s);
  }
  return samples;
}

List<double> generateWinFanfare({int sampleRate = 44100}) {
  final duration = 1.4;
  final numSamples = (sampleRate * duration).toInt();
  final samples = List<double>.filled(numSamples, 0.0);

  // Notes: C5 (523Hz), E5 (659Hz), G5 (784Hz), C6 (1046Hz)
  final notes = [
    {'time': 0.0, 'freq': 523.25, 'dur': 0.25},
    {'time': 0.18, 'freq': 659.25, 'dur': 0.25},
    {'time': 0.36, 'freq': 783.99, 'dur': 0.35},
    {'time': 0.58, 'freq': 1046.50, 'dur': 0.8},
  ];

  for (final note in notes) {
    final startTime = note['time'] as double;
    final freq = note['freq'] as double;
    final noteDur = note['dur'] as double;
    final startIdx = (startTime * sampleRate).toInt();
    final noteSamples = (noteDur * sampleRate).toInt();

    for (int i = 0; i < noteSamples; i++) {
      final targetIdx = startIdx + i;
      if (targetIdx >= numSamples) break;
      final t = i / sampleRate;
      final env = exp(-t * 3.5);
      // Fundamental + harmonics for rich chime
      final s = (sin(2 * pi * freq * t) * 0.6 +
                 sin(2 * pi * freq * 2 * t) * 0.25 +
                 sin(2 * pi * freq * 3 * t) * 0.1) * env;
      samples[targetIdx] += s * 0.7;
    }
  }

  // Normalize
  double maxVal = 0.001;
  for (final s in samples) {
    if (s.abs() > maxVal) maxVal = s.abs();
  }
  return samples.map((s) => (s / maxVal) * 0.95).toList();
}

List<double> generateScratchReveal({int sampleRate = 44100}) {
  final duration = 0.85;
  final numSamples = (sampleRate * duration).toInt();
  final samples = <double>[];
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = sin(pi * min(1.0, t / duration));
    // Upward magical sweep with shimmer
    final freq = 400.0 + pow(t / duration, 2) * 1600.0;
    final s1 = sin(2 * pi * freq * t);
    final s2 = sin(2 * pi * (freq * 1.5) * t) * 0.4;
    final s3 = sin(2 * pi * (freq * 2.0) * t) * 0.2;
    samples.add((s1 + s2 + s3) * env * 0.6);
  }
  return samples;
}

List<double> generateGiftUnlock({int sampleRate = 44100}) {
  final duration = 1.0;
  final numSamples = (sampleRate * duration).toInt();
  final samples = List<double>.filled(numSamples, 0.0);

  final chords = [
    {'time': 0.0, 'freq': 587.33, 'dur': 0.3},  // D5
    {'time': 0.15, 'freq': 880.00, 'dur': 0.35}, // A5
    {'time': 0.30, 'freq': 1174.66, 'dur': 0.7}, // D6
  ];

  for (final chord in chords) {
    final startTime = chord['time'] as double;
    final freq = chord['freq'] as double;
    final chordDur = chord['dur'] as double;
    final startIdx = (startTime * sampleRate).toInt();
    final chordSamples = (chordDur * sampleRate).toInt();

    for (int i = 0; i < chordSamples; i++) {
      final targetIdx = startIdx + i;
      if (targetIdx >= numSamples) break;
      final t = i / sampleRate;
      final env = exp(-t * 4.0);
      final s = (sin(2 * pi * freq * t) * 0.7 + sin(2 * pi * (freq * 2.0) * t) * 0.3) * env;
      samples[targetIdx] += s * 0.6;
    }
  }

  double maxVal = 0.001;
  for (final s in samples) {
    if (s.abs() > maxVal) maxVal = s.abs();
  }
  return samples.map((s) => (s / maxVal) * 0.9).toList();
}

List<double> generateButtonPop({int sampleRate = 44100}) {
  final duration = 0.035; // 35ms
  final numSamples = (sampleRate * duration).toInt();
  final samples = <double>[];
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = exp(-t * 140);
    final freq = 600.0 - (t * 4000.0);
    final s = sin(2 * pi * max(150.0, freq) * t) * env;
    samples.add(s * 0.8);
  }
  return samples;
}

List<double> generateCountdown({int sampleRate = 44100}) {
  final duration = 0.12;
  final numSamples = (sampleRate * duration).toInt();
  final samples = <double>[];
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = exp(-t * 15);
    final s = sin(2 * pi * 880.0 * t) * env;
    samples.add(s * 0.8);
  }
  return samples;
}

void main() {
  final outDir = Directory('${Directory.current.path}/assets/audio');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  File('${outDir.path}/wheel_tick.wav').writeAsBytesSync(createWav(generateWheelTick()));
  File('${outDir.path}/win_fanfare.wav').writeAsBytesSync(createWav(generateWinFanfare()));
  File('${outDir.path}/scratch_reveal.wav').writeAsBytesSync(createWav(generateScratchReveal()));
  File('${outDir.path}/gift_unlock.wav').writeAsBytesSync(createWav(generateGiftUnlock()));
  File('${outDir.path}/button_pop.wav').writeAsBytesSync(createWav(generateButtonPop()));
  File('${outDir.path}/countdown.wav').writeAsBytesSync(createWav(generateCountdown()));

  print('Successfully generated 6 audio files in assets/audio/');
}
