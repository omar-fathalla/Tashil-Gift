import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readBytesFromAudioPath(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  } catch (_) {}
  return Uint8List(0);
}

String getTempAudioPath(String extension) {
  try {
    final tempDir = Directory.systemTemp;
    final now = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/voice_note_$now.$extension';
  } catch (_) {
    return 'voice_note_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }
}
