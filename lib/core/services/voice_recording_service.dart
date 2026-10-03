import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../utils/audio_bytes_helper.dart';

final voiceRecordingServiceProvider = Provider<VoiceRecordingService>((ref) {
  final service = VoiceRecordingService();
  ref.onDispose(() => service.dispose());
  return service;
});

class VoiceRecordingResult {
  final String path;
  final Uint8List bytes;
  final String mimeType;
  final Duration duration;

  const VoiceRecordingResult({
    required this.path,
    required this.bytes,
    required this.mimeType,
    required this.duration,
  });
}

/// Robust, cross-platform voice recording service for AI Brain Studio & Co-Pilot
class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _elapsedSeconds = 0;
  DateTime? _recordStartTime;
  bool _isRecording = false;
  String _currentMimeType = 'audio/wav';

  final _durationStreamController = StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationStreamController.stream;

  bool get isRecording => _isRecording;
  int get elapsedSeconds => _elapsedSeconds;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('Error checking microphone permission: $e');
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      final permitted = await hasPermission();
      if (!permitted) return false;

      // Select encoder: prefer WAV for lossless transcription or fallback to AAC/WebM
      AudioEncoder encoder = AudioEncoder.wav;
      String extension = 'wav';
      _currentMimeType = 'audio/wav';

      final isWavSupported = await _recorder.isEncoderSupported(AudioEncoder.wav);
      if (!isWavSupported) {
        final isAacSupported = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
        if (isAacSupported) {
          encoder = AudioEncoder.aacLc;
          extension = 'm4a';
          _currentMimeType = 'audio/aac';
        } else {
          encoder = AudioEncoder.opus;
          extension = 'webm';
          _currentMimeType = 'audio/webm';
        }
      }

      final targetPath = getTempAudioPath(extension);

      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: targetPath,
      );

      _isRecording = true;
      _elapsedSeconds = 0;
      _recordStartTime = DateTime.now();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedSeconds++;
        _durationStreamController.add(Duration(seconds: _elapsedSeconds));
      });

      return true;
    } catch (e) {
      debugPrint('Error starting voice recording: $e');
      _isRecording = false;
      return false;
    }
  }

  Future<VoiceRecordingResult?> stopRecording() async {
    if (!_isRecording) return null;
    _timer?.cancel();
    _isRecording = false;

    final duration = _recordStartTime != null
        ? DateTime.now().difference(_recordStartTime!)
        : Duration(seconds: _elapsedSeconds);

    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) return null;

      final bytes = await readBytesFromAudioPath(path);

      String mimeType = _currentMimeType;
      if (path.contains('.webm')) {
        mimeType = 'audio/webm';
      } else if (path.contains('.wav')) {
        mimeType = 'audio/wav';
      } else if (path.contains('.m4a') || path.contains('.aac')) {
        mimeType = 'audio/aac';
      } else if (path.contains('.mp3')) {
        mimeType = 'audio/mp3';
      }

      return VoiceRecordingResult(
        path: path,
        bytes: bytes,
        mimeType: mimeType,
        duration: duration,
      );
    } catch (e) {
      debugPrint('Error stopping voice recording: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _timer?.cancel();
    _isRecording = false;
    _elapsedSeconds = 0;
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('Error cancelling voice recording: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    _durationStreamController.close();
    _recorder.dispose();
  }
}
