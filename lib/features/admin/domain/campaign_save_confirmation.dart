import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// N-01: a campaign save counts as done only after the server confirmed it.
///
/// Before N-01 a create that took more than 5 seconds "succeeded" with a new
/// random id (so the links and QR pointed to a campaign that did not exist).
/// Now the id is chosen once before the write, the write is a set() on that
/// id (a retry rewrites the same document, never a second one), and a write
/// that is still pending after [CampaignSaveFlow.wait] is reported as
/// unconfirmed. Only a server read of the document can then confirm it.
///
/// TAG-43: the write keeps running after the wait. When it lands late the
/// save is confirmed automatically; when it fails late the real error (with
/// its code) is reported instead of being dropped.
enum CampaignSaveOutcome { confirmed, unconfirmed }

enum CampaignVerifyResult { confirmed, notYet, failed }

/// Field written with every campaign save. «تحقق» confirms an edit by
/// finding this exact token on the server copy, so no clock is compared.
const String kCampaignSaveTokenField = 'lastSaveToken';

/// A new random token for one save attempt.
String newCampaignSaveToken() {
  final r = math.Random.secure();
  final hex = List<String>.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$hex';
}

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

  // TAG-43
  static const failedTitle = 'الحفظ فشل والحملة ما اتحفظتش';
  static const failedBody =
      'السيرفر رفض الحفظ أو الاتصال وقع. صوّر الرسالة دي وابعتها، وبعدين دوس الحفظ تاني (مش هيعمل حملة مكررة).';
  static const lateConfirmed = 'الحفظ وصل للسيرفر واتأكد ✅';
  static const clearPendingButton = 'مسح الحفظ المعلّق';
  static const clearPendingTitle = 'مسح الحفظ المعلّق من المتصفح ده؟';
  static const clearPendingBody =
      'ده بيمسح من المتصفح ده أي حاجة لسه ما وصلتش للسيرفر: الحملة دي وأي تعديل تاني معلّق. '
      'التعديلات دي هتضيع ولازم تعملها تاني. البيانات اللي على السيرفر مش هتتأثر. '
      'الصفحة هتعمل ريفرش بعد المسح. اقفل أي تاب تانية مفتوح فيها السيستم الأول.';
  static const clearPendingConfirm = 'امسح واعمل ريفرش';
  static const clearPendingCancel = 'رجوع';
  static const clearPendingFailed =
      'ماقدرناش نمسح الحفظ المعلّق، غالبًا فيه تاب تانية مفتوح فيها السيستم. اقفلها كلها وجرّب تاني. الصفحة هتعمل ريفرش دلوقتي.';
  static const leaveTitle = 'الحفظ لسه ما خلصش';
  static const leaveBody = 'لو خرجت دلوقتي ممكن الحملة ما تتحفظش. استنى لحد ما الحفظ يتأكد أو يظهر خطأ.';
  static const leaveStay = 'استنى';
  static const leaveAnyway = 'اخرج برضه';
}

/// TAG-43: the real reason a save failed, kept on screen until the next save.
class CampaignSaveFailure {
  final String code;
  final String message;

  /// True when the error arrived after the wait (the page already showed
  /// "not confirmed yet").
  final bool late;

  const CampaignSaveFailure({required this.code, required this.message, required this.late});

  factory CampaignSaveFailure.from(Object error, {required bool late}) {
    if (error is FirebaseException) {
      return CampaignSaveFailure(code: error.code, message: _clip(error.message ?? ''), late: late);
    }
    return CampaignSaveFailure(code: error.runtimeType.toString(), message: _clip(error.toString()), late: late);
  }

  static String _clip(String s) => s.length > 500 ? s.substring(0, 500) : s;

  /// One line shown to the admin, e.g. "permission-denied: Missing ...".
  String get display => message.isEmpty ? code : '$code: $message';
}

/// The save that is waiting for confirmation.
class PendingCampaignSave {
  final String eventId;
  final bool isNew;
  final String updatedBy;

  /// Written with the save ([kCampaignSaveTokenField]); the server copy
  /// carrying it proves this exact save landed.
  final String saveToken;

  const PendingCampaignSave({required this.eventId, required this.isNew, required this.updatedBy, required this.saveToken});

  /// Whether the server copy [serverData] (null = no document) proves this
  /// save reached the server. A create is proven by the document existing
  /// (the id is unique to this screen); an edit by its token, so a fast or
  /// slow PC clock cannot hide a saved edit.
  bool isConfirmedBy(Map<String, dynamic>? serverData) {
    if (serverData == null) return false;
    if (isNew) return true;
    return (serverData[kCampaignSaveTokenField] ?? '').toString() == saveToken;
  }
}

/// Holds the stable new-campaign id and the pending save of one screen.
class CampaignSaveFlow {
  CampaignSaveFlow({this.wait = const Duration(seconds: 15)});

  final Duration wait;
  String? _newCampaignId;
  PendingCampaignSave? _pending;
  CampaignSaveFailure? _failure;
  int _unsettled = 0;
  int _generation = 0;

  PendingCampaignSave? get pending => _pending;
  bool get isPending => _pending != null;

  /// The real error of the last save, if it failed (cleared by the next save).
  CampaignSaveFailure? get failure => _failure;

  /// True while a write started by [run] has neither landed nor failed, or a
  /// save still waits for confirmation. Leaving the page now may lose it.
  bool get hasUnfinishedSave => _unsettled > 0 || _pending != null;

  /// The id of the campaign being created. [generate] runs once per screen,
  /// so every retry writes the same document.
  String newCampaignId(String Function() generate) => _newCampaignId ??= generate();

  /// Runs [write] for [target]. Returns [CampaignSaveOutcome.confirmed] only
  /// when [write] completed (the server acknowledged it). A write that has
  /// not finished after [wait], or failed with a server deadline, is
  /// [CampaignSaveOutcome.unconfirmed]. Any other error is rethrown.
  ///
  /// TAG-43: a write that was unconfirmed keeps running. If it lands later,
  /// [onLateSuccess] runs (the save is confirmed, nothing pending). If it
  /// fails later, [failure] is set and [onLateError] runs. Both are skipped
  /// when a newer save replaced this one.
  Future<CampaignSaveOutcome> run({
    required PendingCampaignSave target,
    required Future<void> Function() write,
    void Function(PendingCampaignSave target)? onLateSuccess,
    void Function(PendingCampaignSave target, CampaignSaveFailure failure, Object error)? onLateError,
  }) async {
    _pending = null;
    _failure = null;
    final generation = ++_generation;
    final Future<void> future;
    try {
      future = write();
    } catch (e) {
      _failure = CampaignSaveFailure.from(e, late: false);
      rethrow;
    }
    _unsettled++;
    var timedOut = false;
    unawaited(future.then((_) {
      _unsettled--;
      if (!timedOut || generation != _generation) return;
      if (_pending == null) return; // already confirmed by «تحقق» or cleared
      _pending = null;
      onLateSuccess?.call(target);
    }, onError: (Object e) {
      _unsettled--;
      if (!timedOut || generation != _generation) return;
      if (_pending == null) return;
      _pending = null;
      final failure = CampaignSaveFailure.from(e, late: true);
      _failure = failure;
      onLateError?.call(target, failure, e);
    }));
    try {
      await future.timeout(wait);
      return CampaignSaveOutcome.confirmed;
    } on TimeoutException {
      timedOut = true;
      _pending = target;
      return CampaignSaveOutcome.unconfirmed;
    } on FirebaseException catch (e) {
      if (e.code == 'deadline-exceeded' || e.code == 'unavailable') {
        _pending = target;
        _failure = CampaignSaveFailure.from(e, late: false);
        return CampaignSaveOutcome.unconfirmed;
      }
      _failure = CampaignSaveFailure.from(e, late: false);
      rethrow;
    } catch (e) {
      _failure = CampaignSaveFailure.from(e, late: false);
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
