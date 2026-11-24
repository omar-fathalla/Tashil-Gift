import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Index in [list] of the row the editor treats as [draft]'s original.
  /// Exact row identity first, then the page's resolveAllocatedPrize rule
  /// (gift id/name + branch), then its gift-only fallback. Each stored row
  /// is used once, so two draft rows never share one stored row.
  static int matchRow(List<AllocatedPrize> list, AllocatedPrize draft, Set<int> used) {
    final key = draft.giftId;
    final dKey = _rowKey(draft);
    for (var i = 0; i < list.length; i++) {
      if (!used.contains(i) && _rowKey(list[i]) == dKey) return i;
    }
    bool sameGift(AllocatedPrize p) => p.giftId == key || p.name == key;
    for (var i = 0; i < list.length; i++) {
      final p = list[i];
      if (used.contains(i) || !sameGift(p)) continue;
      if (draft.branchId.isEmpty || p.branchId == draft.branchId || p.branchName == draft.branchName) return i;
    }
    for (var i = 0; i < list.length; i++) {
      if (!used.contains(i) && sameGift(list[i])) return i;
    }
    return -1;
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
    final usedOpened = <int>{};
    final openedOf = <int>[];
    var changed = false;
    for (final d in draftRows) {
      final o = matchRow(opened, d, usedOpened);
      openedOf.add(o);
      if (o >= 0) {
        usedOpened.add(o);
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
    final usedCurrent = <int>{};
    final out = <Map<String, dynamic>>[];
    final problems = <String>[];
    for (var j = 0; j < draftRows.length; j++) {
      final d = draftRows[j];
      final c = matchRow(current, d, usedCurrent);
      if (c < 0) {
        out.add(d.copyWith(remainingQuantity: d.allocatedQuantity).toMap());
        continue;
      }
      usedCurrent.add(c);
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
  static Future<void> save({
    required FirebaseFirestore firestore,
    required EventModel draft,
    required EventModel opened,
    required String updatedBy,
  }) {
    final ref = firestore.collection('events').doc(opened.id);
    return firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (!snap.exists || data == null) {
        throw const CampaignEditRejected('الحملة غير موجودة أو تم حذفها، ولم يتم حفظ التعديل.');
      }
      tx.update(ref, buildEditPatch(draft: draft, opened: opened, currentData: data, updatedBy: updatedBy));
    }, timeout: const Duration(seconds: 30));
  }
}
