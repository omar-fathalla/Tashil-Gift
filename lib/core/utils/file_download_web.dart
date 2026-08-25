// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web implementation for triggering browser file downloads
void downloadFileBytes({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
