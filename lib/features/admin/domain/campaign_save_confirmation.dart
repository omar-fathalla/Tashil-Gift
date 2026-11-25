import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// N-01: a campaign save counts as done only after the server confirmed it.
///
/// Before N-01 a create that took more than 5 seconds "succeeded" with a new
/// random id (so the links and QR pointed to a campaign that did not exist).
/// Now the id is chosen once before the write, the write is a set() on that
/// id (a retry rewrites the same document, never a second one), and a write
/// that is still pending after [CampaignSaveFlow.wait] is reported as
/// unconfirmed. Only a server read of the document can then confirm it.
enum CampaignSaveOutcome { confirmed, unconfirmed }

enum CampaignVerifyResult { confirmed, notYet, failed }

/// Arabic texts of the unconfirmed state (shared by the screen and tests).
class CampaignSaveTexts {
  static const unconfirmedTitle = 'الحفظ لسه ما اتأكدش';
  static const unconfirmedBody =
      'الحملة لسه ما وصلتش للسيرفر، وممكن يكون النت بطيء. ماتقفلش الصفحة، ودوس «تحقق» عشان نتأكد إن الحملة اتحفظت. '
      'الروابط ورمز QR هيظهروا بعد التأكيد بس.';
  static const verifyButton = 'تحقق';
  static const notYet = 'الحملة لسه مش موجودة على السيرفر. اتأكد من النت ودوس «تحقق» تاني، أو دوس الحفظ تاني (مش هيعمل حملة مكررة).';
  static const verifyFailed = 'ماقدرناش نوصل للسيرفر عشان نتأكد. اتأكد من النت وجرّب «تحقق» تاني.';
  static const chainBranchUnconfirmed = 'الحفظ لسه ما اتأكدش. دوس «تحقق» بعد ما النت يرجع.';
}

/// The save that is waiting for confirmation.
class PendingCampaignSave {
  final String eventId;
  final bool isNew;
  final String updatedBy;

  /// Client time just before the write; an edit is confirmed when the server
  /// copy was updated by the same admin at or after this moment.
  final DateTime startedAt;

  const PendingCampaignSave({required this.eventId, required this.isNew, required this.updatedBy, required this.startedAt});

  /// Whether the server copy [serverData] (null = no document) proves this
  /// save reached the server.
  bool isConfirmedBy(Map<String, dynamic>? serverData) {
    if (serverData == null) return false;
    if (isNew) return true;
    if ((serverData['updatedBy'] ?? '').toString() != updatedBy) return false;
    final raw = serverData['updatedAt'];
    final at = raw is Timestamp ? raw.toDate() : (raw is DateTime ? raw : null);
    return at != null && !at.isBefore(startedAt);
  }
}

/// Holds the stable new-campaign id and the pending save of one screen.
class CampaignSaveFlow {
  CampaignSaveFlow({this.wait = const Duration(seconds: 15)});

  final Duration wait;
  String? _newCampaignId;
  PendingCampaignSave? _pending;

  PendingCampaignSave? get pending => _pending;
  bool get isPending => _pending != null;

  /// The id of the campaign being created. [generate] runs once per screen,
  /// so every retry writes the same document.
  String newCampaignId(String Function() generate) => _newCampaignId ??= generate();

  /// Runs [write] for [target]. Returns [CampaignSaveOutcome.confirmed] only
  /// when [write] completed (the server acknowledged it). A write that has
  /// not finished after [wait], or failed with a server deadline, is
  /// [CampaignSaveOutcome.unconfirmed]. Any other error is rethrown.
  Future<CampaignSaveOutcome> run({required PendingCampaignSave target, required Future<void> Function() write}) async {
    _pending = null;
    final future = write();
    // A late error after the wait is already reported as unconfirmed.
    unawaited(future.then((_) {}, onError: (Object _) {}));
    try {
      await future.timeout(wait);
      return CampaignSaveOutcome.confirmed;
    } on TimeoutException {
      _pending = target;
      return CampaignSaveOutcome.unconfirmed;
    } on FirebaseException catch (e) {
      if (e.code == 'deadline-exceeded' || e.code == 'unavailable') {
        _pending = target;
        return CampaignSaveOutcome.unconfirmed;
      }
      rethrow;
    }
  }

  /// Reads the pending campaign with [readFromServer] (must read from the
  /// server, not the cache) and confirms it only if the server copy proves
  /// the save. Clears the pending state on confirmation.
  Future<CampaignVerifyResult> verify(Future<Map<String, dynamic>?> Function(String eventId) readFromServer) async {
    final target = _pending;
    if (target == null) return CampaignVerifyResult.confirmed;
    try {
      final data = await readFromServer(target.eventId);
      if (target.isConfirmedBy(data)) {
        _pending = null;
        return CampaignVerifyResult.confirmed;
      }
      return CampaignVerifyResult.notYet;
    } catch (_) {
      return CampaignVerifyResult.failed;
    }
  }

  void clearPending() => _pending = null;
}

/// N-01: a chain/branch write that was not confirmed in time. [path] is the
/// document to read from the server before treating it as saved.
class WriteNotConfirmedException implements Exception {
  final String path;
  const WriteNotConfirmedException(this.path);
  @override
  String toString() => CampaignSaveTexts.chainBranchUnconfirmed;
}

/// Reads [ref] from the server only (never the cache).
Future<Map<String, dynamic>?> readCampaignDocFromServer(DocumentReference<Map<String, dynamic>> ref) async {
  final snap = await ref.get(const GetOptions(source: Source.server));
  return snap.exists ? snap.data() : null;
}
