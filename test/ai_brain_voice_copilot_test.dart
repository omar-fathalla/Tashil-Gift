import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/ai_brain_copilot_service.dart';
import 'package:al_mraay/core/services/voice_recording_service.dart';
import 'package:al_mraay/features/admin/domain/ai_directives_seed_data.dart';
import 'package:al_mraay/features/admin/domain/ai_directive_model.dart';

void main() {
  group('AI Brain Voice Co-Pilot & Directives Tests', () {
    test('AiBrainChatMessage supports voice note fields and transcription', () {
      final dummyBytes = Uint8List.fromList([0, 1, 2, 3, 4]);
      final msg = AiBrainChatMessage(
        id: 'voice_msg_1',
        isUser: true,
        text: '🎙️ تسجيل صوتي مرسل إلى عقل الذكاء الاصطناعي',
        audioBytes: dummyBytes,
        audioPath: 'blob:http://localhost/test-uuid',
        audioMimeType: 'audio/wav',
        audioDuration: const Duration(seconds: 14),
        voiceTranscription: 'عاوزين نعمل قاعدة لو العميل اشترى عبوتين ديفا 500 مل ياخد قسيمة 25 جنيه',
        timestamp: DateTime.now(),
      );

      expect(msg.audioBytes, isNotNull);
      expect(msg.audioBytes!.length, 5);
      expect(msg.audioPath, 'blob:http://localhost/test-uuid');
      expect(msg.audioMimeType, 'audio/wav');
      expect(msg.audioDuration?.inSeconds, 14);
      expect(msg.voiceTranscription, contains('عبوتين ديفا'));
    });

    test('VoiceRecordingResult encapsulates audio recording metadata properly', () {
      final dummyBytes = Uint8List.fromList([10, 20, 30, 40]);
      final result = VoiceRecordingResult(
        path: '/tmp/test_voice.wav',
        bytes: dummyBytes,
        mimeType: 'audio/wav',
        duration: const Duration(seconds: 8),
      );

      expect(result.path, '/tmp/test_voice.wav');
      expect(result.bytes.length, 4);
      expect(result.mimeType, 'audio/wav');
      expect(result.duration.inSeconds, 8);
    });

    test('AIR-62 Directive is registered in AI Brain seed data with correct metadata', () {
      final air62 = AiDirectivesSeedData.initialDirectives.firstWhere(
        (d) => d.id == 'AIR-62',
      );

      expect(air62, isNotNull);
      expect(air62.code, 'MULTIMODAL_VOICE_INTERACTION_AND_AUDIO_DIRECTIVES_TEACHING_ENGINE');
      expect(air62.category, AiDirectiveCategory.nlpMatching);
      expect(air62.titleAr, contains('التفاعل الصوتي'));
      expect(air62.descriptionAr, contains('التحدث بالصوت الطبيعي'));
      expect(air62.tags, contains('voice-recording'));
      expect(air62.tags, contains('speech-to-text'));
    });
  });
}
