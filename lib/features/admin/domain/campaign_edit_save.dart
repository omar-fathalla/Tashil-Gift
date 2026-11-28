import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/campaign_content_repository.dart';
import 'event_model.dart';

/// Campaign edit refused before any write (Arabic message for the admin).
class CampaignEditRejected implements Exception {
  final String message;
  const CampaignEditRejected(this.message);
  @override
  String toString() => message;
}

/// C-02: safe campaign edit save.
///
/// The editor holds the copy loaded when the page opened ([opened]). Claims
/// keep decrementing the stored rows meanwhile, so the save must be built from
/// the document read inside the transaction ([currentData]):
///  * only editor-owned fields the admin changed (draft vs opened) are written,
///    never isActive / portal toggles / spendLadderMode;
///  * allocatedPrizes is written only when quantities or rows changed, and then
///    each changed row gets remaining = current remaining + (new total - current total).
class CampaignEditSave {
  CampaignEditSave._();

  static String _key(String branchId, String branchName, String giftId, String name) {
    final b = branchId.isNotEmpty ? branchId : branchName.trim().toLowerCase();
    final g = giftId.isNotEmpty ? giftId : name.trim().toLowerCase();
    return '${b}_$g';
  }

  static String _rowKey(AllocatedPrize p) => _key(p.branchId, p.branchName, p.giftId, p.name);

  /// Same de-duplication EventModel.toFirestore applies to the draft rows.
  static List<AllocatedPrize> _dedupe(List<AllocatedPrize> list) {
    final seen = <String>{};
    return [for (final p in list) if (seen.add(_rowKey(p))) p];
  }

  static int _consumed(AllocatedPrize p) {
    final c = p.allocatedQuantity - p.remainingQuantity;
    return c < 0 ? 0 : c;
  }

  static bool _sameGift(AllocatedPrize stored, AllocatedPrize draft) =>
      stored.giftId == draft.giftId || stored.name == draft.giftId;

  static bool _isGeneral(AllocatedPrize p) => p.branchId.isEmpty && p.branchName.trim().isEmpty;

  static bool _sameBranch(AllocatedPrize stored, AllocatedPrize draft) =>
      stored.branchId == draft.branchId ||
      (draft.branchName.trim().isNotEmpty && stored.branchName.trim() == draft.branchName.trim());

  /// For each row of [drafts], the index in [list] of the stored row the editor
  /// treats as its original, or -1 for a new row. Each stored row is matched at
  /// most once. Matching runs in passes over ALL draft rows, so a new branch
  /// row listed first can never take an existing branch's row:
  ///  1. exact identity (gift id/name + branch id/name);
  ///  2. the page's resolveAllocatedPrize rule (same gift, same branch, or the
  ///     draft row is general);
  ///  3. gift-only fallback, only for general rows or rows whose gift has no
  ///     stored row at their own branch.
  static List<int> matchRows(List<AllocatedPrize> list, List<AllocatedPrize> drafts) {
    final result = List<int>.filled(drafts.length, -1);
    final used = <int>{};

    void pass(bool Function(AllocatedPrize stored, AllocatedPrize draft) accepts,
        {bool Function(AllocatedPrize draft)? eligible}) {
      for (var j = 0; j < drafts.length; j++) {
        if (result[j] >= 0) continue;
        final d = drafts[j];
        if (eligible != null && !eligible(d)) continue;
        for (var i = 0; i < list.length; i++) {
          if (used.contains(i) || !accepts(list[i], d)) continue;
          result[j] = i;
          used.add(i);
          break;
        }
      }
    }

    pass((p, d) => _rowKey(p) == _rowKey(d));
    pass((p, d) => _sameGift(p, d) && (d.branchId.isEmpty || _sameBranch(p, d)));
    pass(
      _sameGift,
      eligible: (d) => _isGeneral(d) || !list.any((p) => _sameGift(p, d) && _sameBranch(p, d)),
    );
    return result;
  }

  static String _label(AllocatedPrize p) {
    final branch = p.branchName.trim().isNotEmpty ? p.branchName.trim() : (p.branchId.isNotEmpty ? p.branchId : 'كل الفروع');
    return '"${p.name}" في "$branch"';
  }

  /// Stock rows to write, or null when the admin changed no quantity and no row.
  ///
  /// [currentRaw] is the stored allocatedPrizes list read in the transaction;
  /// rows the admin did not touch are written back exactly as stored.
  /// Throws [CampaignEditRejected] when a total drops below what was already
  /// handed out, or a row with handed-out stock is removed.
  static List<Map<String, dynamic>>? mergeAllocationsForEdit({
    required List<AllocatedPrize> opened,
    required List<AllocatedPrize> draft,
    required List<Map<String, dynamic>> currentRaw,
  }) {
    final draftRows = _dedupe(draft);

    // 1. What did the admin change compared with the copy they opened?
    final openedOf = matchRows(opened, draftRows);
    final usedOpened = {for (final o in openedOf) if (o >= 0) o};
    var changed = false;
    for (var j = 0; j < draftRows.length; j++) {
      final o = openedOf[j];
      final d = draftRows[j];
      if (o >= 0) {
        if (opened[o].allocatedQuantity != d.allocatedQuantity) changed = true;
      } else if (d.allocatedQuantity > 0) {
        changed = true;
      }
    }
    final removedOpened = <int>[
      for (var i = 0; i < opened.length; i++)
        if (!usedOpened.contains(i)) i,
    ];
    if (removedOpened.any((i) => opened[i].allocatedQuantity > 0)) changed = true;
    if (!changed) return null;

    // 2. Rebuild from the stored rows read in the transaction.
    final current = currentRaw.map(AllocatedPrize.fromMap).toList();
    final currentOf = matchRows(current, draftRows);
    final usedCurrent = {for (final c in currentOf) if (c >= 0) c};
    final out = <Map<String, dynamic>>[];
    final problems = <String>[];
    for (var j = 0; j < draftRows.length; j++) {
      final d = draftRows[j];
      final c = currentOf[j];
      if (c < 0) {
        out.add(d.copyWith(remainingQuantity: d.allocatedQuantity).toMap());
        continue;
      }
      final cur = current[c];
      final o = openedOf[j];
      final untouched = o >= 0 && opened[o].allocatedQuantity == d.allocatedQuantity;
      if (untouched) {
        out.add(Map<String, dynamic>.from(currentRaw[c]));
        continue;
      }
      final consumed = _consumed(cur);
      if (d.allocatedQuantity < consumed) {
        problems.add('${_label(cur)}: الكمية الجديدة ${d.allocatedQuantity} أقل من المصروف فعلاً $consumed');
        continue;
      }
      final remaining = cur.remainingQuantity + (d.allocatedQuantity - cur.allocatedQuantity);
      out.add(d.copyWith(remainingQuantity: remaining < 0 ? 0 : remaining).toMap());
    }

    // 3. Stored rows the draft no longer has.
    final removedKeys = {for (final i in removedOpened) _rowKey(opened[i])};
    for (var i = 0; i < current.length; i++) {
      if (usedCurrent.contains(i)) continue;
      final cur = current[i];
      if (removedKeys.contains(_rowKey(cur))) {
        if (_consumed(cur) > 0) {
          problems.add('${_label(cur)}: لا يمكن حذف هدية تم صرف ${_consumed(cur)} منها');
        }
        continue; // removed by the admin
      }
      out.add(Map<String, dynamic>.from(currentRaw[i])); // added by someone else meanwhile
    }

    if (problems.isNotEmpty) {
      throw CampaignEditRejected(
        'لم يتم حفظ التعديل لأن أرصدة الهدايا لا تسمح بذلك:\n'
        '${problems.map((e) => '• $e').join('\n')}\n'
        'لم يتغير أي شيء في الحملة.',
      );
    }
    return out;
  }

  static bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// The update() payload for an edit: changed editor fields only, the merged
  /// stock rows when needed, plus updatedAt/updatedBy.
  static Map<String, dynamic> buildEditPatch({
    required EventModel draft,
    required EventModel opened,
    required Map<String, dynamic> currentData,
    required String updatedBy,
  }) {
    final draftMap = draft.toFirestore();
    final openedMap = opened.toFirestore();
    final patch = <String, dynamic>{};
    for (final key in EventModel.campaignEditorOwnedFields) {
      if (key == 'allocatedPrizes') continue;
      if (!draftMap.containsKey(key)) continue;
      if (!_deepEquals(draftMap[key], openedMap[key])) patch[key] = draftMap[key];
    }
    final rawList = currentData['allocatedPrizes'];
    final currentRaw = <Map<String, dynamic>>[
      if (rawList is List)
        for (final r in rawList)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
    final prizes = mergeAllocationsForEdit(
      opened: opened.allocatedPrizes,
      draft: draft.allocatedPrizes,
      currentRaw: currentRaw,
    );
    if (prizes != null) patch['allocatedPrizes'] = prizes;
    patch['updatedAt'] = FieldValue.serverTimestamp();
    patch['updatedBy'] = updatedBy;
    return patch;
  }

  /// Runs the edit as one transaction on the stored campaign. No silent
  /// success: offline / timeout / rejection all throw to the caller.
  ///
  /// A rejection is never thrown inside the transaction handler: on web,
  /// FlutterFire wraps a Dart error thrown there into a JS error, so the
  /// caller would lose the [CampaignEditRejected] type and its Arabic message.
  /// The handler records the outcome in a [CampaignEditAttempt] instead
  /// (runTransaction also returns null on web, so the result cannot be the
  /// handler's return value), and the rejection is thrown after the
  /// transaction has finished.
  static Future<void> save({
    required FirebaseFirestore firestore,
    required EventModel draft,
    required EventModel opened,
    required String updatedBy,
  }) async {
    final ref = firestore.collection('events').doc(opened.id);
    final attempt = CampaignEditAttempt(draft: draft, opened: opened, updatedBy: updatedBy);
    await firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final patch = attempt.plan(snap.exists ? snap.data() : null);
      if (patch != null) tx.update(ref, patch);
      // TAG-62: products / prompt docs in the same transaction as the patch.
      final content = attempt.contentWrite;
      if (patch != null && content != null) {
        CampaignContentRepository(firestore).writeInTransaction(tx, opened.id, content);
      }
    }, timeout: const Duration(seconds: 30));
    attempt.throwIfRejected();
  }
}

/// Outcome of one transaction attempt of [CampaignEditSave.save]: either the
/// update() payload or the Arabic rejection message, never an exception
/// thrown inside the transaction handler.
class CampaignEditAttempt {
  final EventModel draft;
  final EventModel opened;
  final String updatedBy;
  String? _rejection;
  CampaignContentWrite? _contentWrite;

  /// TAG-62: content docs the latest planned patch goes with (null = none).
  CampaignContentWrite? get contentWrite => _contentWrite;

  CampaignEditAttempt({required this.draft, required this.opened, required this.updatedBy});

  /// Rejection message of the latest attempt, or null if it can be written.
  String? get rejection => _rejection;

  /// Patch to write for the stored campaign [currentData] (null when the
  /// document is missing), or null when the edit is rejected. Each call
  /// replaces the previous outcome, so a retried transaction reports only
  /// its last attempt.
  Map<String, dynamic>? plan(Map<String, dynamic>? currentData) {
    _rejection = null;
    _contentWrite = null;
    if (currentData == null) {
      _rejection = 'الحملة غير موجودة أو تم حذفها، ولم يتم حفظ التعديل.';
      return null;
    }
    try {
      final patch = CampaignEditSave.buildEditPatch(
        draft: draft,
        opened: opened,
        currentData: currentData,
        updatedBy: updatedBy,
      );
      // TAG-62: changed products/prompt (or a stored copy too large to keep
      // inline) go to events/{id}/content; the patch gets the content fields.
      final content = CampaignContentRepository.planForEdit(
        patch: patch,
        draft: draft,
        currentData: currentData,
      );
      _contentWrite = content;
      return content == null ? patch : content.applyToPatch(patch);
    } on CampaignEditRejected catch (e) {
      _rejection = e.message;
      return null;
    } on CampaignContentTooLarge catch (e) {
      _rejection = '${e.message}\nلم يتغير أي شيء في الحملة.';
      return null;
    }
  }

  /// Throws [CampaignEditRejected] outside the transaction if the latest
  /// attempt was rejected.
  void throwIfRejected() {
    final message = _rejection;
    if (message != null) throw CampaignEditRejected(message);
  }
}
