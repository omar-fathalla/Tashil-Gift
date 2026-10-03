// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

StreamSubscription? listenToClipboardImagePaste(void Function(Uint8List imageBytes) onImagePasted) {
  try {
    return html.document.onPaste.listen((html.ClipboardEvent event) {
      final items = event.clipboardData?.items;
      bool handledAny = false;

      if (items != null) {
        final int count = items.length ?? 0;
        for (var i = 0; i < count; i++) {
          final item = items[i];
          if (item.type != null && item.type!.startsWith('image/')) {
            final blob = item.getAsFile();
            if (blob != null) {
              handledAny = true;
              final reader = html.FileReader();
              reader.readAsArrayBuffer(blob);
              reader.onLoadEnd.listen((_) {
                final res = reader.result;
                if (res is Uint8List) {
                  onImagePasted(res);
                } else if (res is ByteBuffer) {
                  onImagePasted(res.asUint8List());
                }
              });
            }
          }
        }
      }

      if (!handledAny) {
        final files = event.clipboardData?.files;
        if (files != null && files.isNotEmpty) {
          for (final file in files) {
            if (file.type.startsWith('image/')) {
              final reader = html.FileReader();
              reader.readAsArrayBuffer(file);
              reader.onLoadEnd.listen((_) {
                final res = reader.result;
                if (res is Uint8List) {
                  onImagePasted(res);
                } else if (res is ByteBuffer) {
                  onImagePasted(res.asUint8List());
                }
              });
            }
          }
        }
      }
    });
  } catch (_) {
    return null;
  }
}
