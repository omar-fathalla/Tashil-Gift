import 'dart:typed_data';

import '../../../core/services/firebase_service.dart';

/// Storage prefix for WhatsApp campaign posters and PDFs.
///
/// Objects live at `whatsapp_campaign_media/{uid}/{timestamp}_{fileName}`.
/// The send path stores a Firebase download URL (`getDownloadURL`): an https
/// link with an unguessable token. WAHA fetches that link with a normal GET
/// while sending to each recipient, so the URL must not depend on the admin's
/// browser session. Listing the prefix is denied. The token does not expire
/// during a long send unless the object is deleted.
const String kWhatsAppCampaignMediaPrefix = 'whatsapp_campaign_media';

/// 20 MiB. Large enough for a campaign PDF, small enough to reject accidents.
const int kWhatsAppCampaignMediaMaxBytes = 20 * 1024 * 1024;

/// Why an upload was refused before anything is stored.
enum WhatsAppCampaignMediaFailure {
  unauthorized,
  missingUser,
  unsupportedType,
  empty,
  tooLarge,
  uploadFailed,
}

class WhatsAppCampaignMediaUploadException implements Exception {
  final WhatsAppCampaignMediaFailure failure;

  const WhatsAppCampaignMediaUploadException(this.failure);

  @override
  String toString() => 'WhatsAppCampaignMediaUploadException(${failure.name})';
}

/// What the existing send path should attach. An uploaded file wins over a pasted link.
class WhatsAppCampaignOutboundSelection {
  final String? url;
  final String? fileName;
  final String? mimeType;

  const WhatsAppCampaignOutboundSelection({
    this.url,
    this.fileName,
    this.mimeType,
  });
}

WhatsAppCampaignOutboundSelection resolveWhatsAppCampaignOutboundMedia({
  required bool mediaMode,
  WhatsAppCampaignMediaAttachment? uploaded,
  required String pastedUrl,
}) {
  if (!mediaMode) {
    return const WhatsAppCampaignOutboundSelection();
  }
  final stored = uploaded?.downloadUrl.trim() ?? '';
  if (uploaded != null && stored.isNotEmpty) {
    return WhatsAppCampaignOutboundSelection(
      url: stored,
      fileName: uploaded.fileName,
      mimeType: uploaded.mimeType,
    );
  }
  final pasted = pastedUrl.trim();
  if (pasted.isEmpty) {
    return const WhatsAppCampaignOutboundSelection();
  }
  return WhatsAppCampaignOutboundSelection(url: pasted);
}

/// A file that has been stored and is ready to attach to the campaign send.
class WhatsAppCampaignMediaAttachment {
  final String downloadUrl;
  final String fileName;
  final String displayName;
  final String mimeType;
  final String storagePath;
  final bool isPdf;

  const WhatsAppCampaignMediaAttachment({
    required this.downloadUrl,
    required this.fileName,
    required this.displayName,
    required this.mimeType,
    required this.storagePath,
    required this.isPdf,
  });
}

class WhatsAppCampaignFileKind {
  final String mimeType;
  final String extension;
  final bool isPdf;

  const WhatsAppCampaignFileKind({
    required this.mimeType,
    required this.extension,
    required this.isPdf,
  });
}

/// Staff who can already open the WhatsApp marketing page.
bool canManageWhatsAppCampaignMedia({
  required String? role,
  required bool isAnonymous,
}) {
  if (isAnonymous) return false;
  return isStaffRole(role);
}

/// Detects PDF vs image from file bytes, then the declared content type, then
/// the extension. Bytes win when they identify a supported file, so a pasted
/// name cannot relabel a JPEG as a PDF.
WhatsAppCampaignFileKind? detectWhatsAppCampaignFileKind({
  required String fileName,
  String? contentType,
  Uint8List? bytes,
}) {
  if (bytes != null && bytes.isNotEmpty) {
    return sniffWhatsAppCampaignBytes(bytes);
  }

  final declared = normalizeWhatsAppCampaignMime(contentType);
  final fromName = whatsAppCampaignKindFromExtension(fileExtensionOf(fileName));
  if (declared != null) {
    if (fromName != null && fromName.mimeType != declared) return null;
    return kindFromWhatsAppCampaignMime(declared);
  }
  final rawType = (contentType ?? '').trim();
  if (rawType.isNotEmpty) return null;
  return fromName;
}

String? normalizeWhatsAppCampaignMime(String? contentType) {
  final mime = (contentType ?? '').toLowerCase().split(';').first.trim();
  switch (mime) {
    case 'application/pdf':
      return 'application/pdf';
    case 'image/jpeg':
    case 'image/jpg':
      return 'image/jpeg';
    case 'image/png':
      return 'image/png';
    case 'image/webp':
      return 'image/webp';
    default:
      return null;
  }
}

WhatsAppCampaignFileKind? kindFromWhatsAppCampaignMime(String mimeType) {
  switch (mimeType) {
    case 'application/pdf':
      return const WhatsAppCampaignFileKind(
        mimeType: 'application/pdf',
        extension: 'pdf',
        isPdf: true,
      );
    case 'image/jpeg':
      return const WhatsAppCampaignFileKind(
        mimeType: 'image/jpeg',
        extension: 'jpg',
        isPdf: false,
      );
    case 'image/png':
      return const WhatsAppCampaignFileKind(
        mimeType: 'image/png',
        extension: 'png',
        isPdf: false,
      );
    case 'image/webp':
      return const WhatsAppCampaignFileKind(
        mimeType: 'image/webp',
        extension: 'webp',
        isPdf: false,
      );
    default:
      return null;
  }
}

WhatsAppCampaignFileKind? whatsAppCampaignKindFromExtension(String? extension) {
  switch ((extension ?? '').toLowerCase()) {
    case 'pdf':
      return kindFromWhatsAppCampaignMime('application/pdf');
    case 'jpg':
    case 'jpeg':
      return kindFromWhatsAppCampaignMime('image/jpeg');
    case 'png':
      return kindFromWhatsAppCampaignMime('image/png');
    case 'webp':
      return kindFromWhatsAppCampaignMime('image/webp');
    default:
      return null;
  }
}

String? fileExtensionOf(String fileName) {
  final base = fileName
      .split('?')
      .first
      .split('#')
      .first
      .split(RegExp(r'[\\/]'))
      .last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return null;
  return base.substring(dot + 1).toLowerCase();
}

/// Recognizes a PDF within the first 1024 bytes, or an image signature at the start.
WhatsAppCampaignFileKind? sniffWhatsAppCampaignBytes(Uint8List bytes) {
  if (_containsPdfHeader(bytes)) {
    return kindFromWhatsAppCampaignMime('application/pdf');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return kindFromWhatsAppCampaignMime('image/jpeg');
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return kindFromWhatsAppCampaignMime('image/png');
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return kindFromWhatsAppCampaignMime('image/webp');
  }
  return null;
}

bool _containsPdfHeader(Uint8List bytes) {
  final limit = bytes.length < 1024 ? bytes.length : 1024;
  for (var i = 0; i <= limit - 5; i++) {
    if (bytes[i] == 0x25 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x44 &&
        bytes[i + 3] == 0x46 &&
        bytes[i + 4] == 0x2D) {
      return true;
    }
  }
  return false;
}

String displayNameForWhatsAppCampaignFile(String rawName) {
  final base = rawName.split(RegExp(r'[\\/]')).last.trim();
  final cleaned = base.replaceAll(RegExp(r'[\u0000-\u001F]'), '').trim();
  if (cleaned.isEmpty) return 'campaign_file';
  if (cleaned.length <= 120) return cleaned;
  return cleaned.substring(0, 120);
}

/// Keeps Arabic letters and safe ASCII. Drops path separators and extra dots.
String sanitizeWhatsAppCampaignFileName(
  String rawName, {
  required String extension,
}) {
  final ext = extension.toLowerCase();
  var base = displayNameForWhatsAppCampaignFile(rawName);
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9\u0600-\u06FF]+'), '_');
  base = base.replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'campaign_file';
  if (base.length > 60) {
    base = base.substring(0, 60).replaceAll(RegExp(r'_+$'), '');
    if (base.isEmpty) base = 'campaign_file';
  }
  return '$base.$ext';
}

String whatsAppCampaignMediaStoragePath({
  required String uid,
  required int timestampMs,
  required String sanitizedFileName,
}) {
  final cleanUid = uid.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(cleanUid)) {
    throw ArgumentError('Invalid uploader id');
  }
  if (timestampMs <= 0) {
    throw ArgumentError('Invalid timestamp');
  }
  if (sanitizedFileName.contains('/') ||
      sanitizedFileName.contains('\\') ||
      sanitizedFileName.contains('..') ||
      sanitizedFileName.trim().isEmpty) {
    throw ArgumentError('Invalid file name');
  }
  return '$kWhatsAppCampaignMediaPrefix/$cleanUid/${timestampMs}_$sanitizedFileName';
}

/// Storage port so upload authorization can be tested without Firebase.
abstract class WhatsAppCampaignMediaStorage {
  Future<String> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    void Function(int transferred, int total)? onProgress,
  });

  Future<void> delete(String storagePath);
}

class WhatsAppCampaignMediaUploader {
  final WhatsAppCampaignMediaStorage storage;
  final Future<bool> Function() authorize;
  final String? Function() currentUid;
  final int Function() nowMillis;

  WhatsAppCampaignMediaUploader({
    required this.storage,
    required this.authorize,
    required this.currentUid,
    int Function()? nowMillis,
  }) : nowMillis = nowMillis ?? _defaultNowMillis;

  static int _defaultNowMillis() => DateTime.now().millisecondsSinceEpoch;

  Future<WhatsAppCampaignMediaAttachment> upload({
    required Uint8List bytes,
    required String fileName,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (!await authorize()) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.unauthorized,
      );
    }
    final uid = currentUid()?.trim() ?? '';
    if (uid.isEmpty) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.missingUser,
      );
    }
    if (bytes.isEmpty) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.empty,
      );
    }
    if (bytes.length > kWhatsAppCampaignMediaMaxBytes) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.tooLarge,
      );
    }
    final kind = detectWhatsAppCampaignFileKind(
      fileName: fileName,
      contentType: contentType,
      bytes: bytes,
    );
    if (kind == null) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.unsupportedType,
      );
    }
    final safeName = sanitizeWhatsAppCampaignFileName(
      fileName,
      extension: kind.extension,
    );
    final path = whatsAppCampaignMediaStoragePath(
      uid: uid,
      timestampMs: nowMillis(),
      sanitizedFileName: safeName,
    );
    final url = await storage.upload(
      storagePath: path,
      bytes: bytes,
      contentType: kind.mimeType,
      customMetadata: {
        'uploaderUid': uid,
        'originalFileName': displayNameForWhatsAppCampaignFile(fileName),
      },
      onProgress: (transferred, total) {
        if (onProgress == null || total <= 0) return;
        onProgress((transferred / total).clamp(0.0, 1.0).toDouble());
      },
    );
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const WhatsAppCampaignMediaUploadException(
        WhatsAppCampaignMediaFailure.uploadFailed,
      );
    }
    return WhatsAppCampaignMediaAttachment(
      downloadUrl: trimmedUrl,
      fileName: safeName,
      displayName: displayNameForWhatsAppCampaignFile(fileName),
      mimeType: kind.mimeType,
      storagePath: path,
      isPdf: kind.isPdf,
    );
  }

  Future<void> delete(String storagePath) async {
    if (!storagePath.startsWith('$kWhatsAppCampaignMediaPrefix/')) return;
    if (!await authorize()) return;
    try {
      await storage.delete(storagePath);
    } catch (_) {}
  }
}
