// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List> readBytesFromAudioPath(String path) async {
  try {
    final request = await html.HttpRequest.request(
      path,
      responseType: 'arraybuffer',
    );
    final response = request.response;
    if (response is ByteBuffer) {
      return response.asUint8List();
    } else if (response is Uint8List) {
      return response;
    }
  } catch (_) {}
  return Uint8List(0);
}

String getTempAudioPath(String extension) => '';
