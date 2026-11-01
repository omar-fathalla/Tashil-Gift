import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';
import 'arabic_numbers_utils.dart';

/// Deterministic branch resolution from the store code printed inside the
/// receipt number (2.0.153+214).
///
/// Many chains print the store code as a fixed segment of the receipt number,
/// e.g. Fathalla `145/10/224/301026` where `224` (the segment before the
/// trailing date) is the store code, matching branch pattern `224/YYMMDD`.
/// The position is read per branch from `receiptSignature.receiptPattern`
/// (the segment holding the branch's own code, counted from the end). With no
/// pattern, the default layout is "code right before a trailing 6-8 digit
/// date". A match only counts when exactly one branch of the chain owns the
/// code; otherwise callers keep the AI's branch.
class StoreCodeBranchResolver {
  StoreCodeBranchResolver._();

  static List<String> segments(String raw) => raw
      .toEnglishDigits()
      .trim()
      .split(RegExp(r'[\/\-\\\s]+'))
      .where((s) => s.isNotEmpty)
      .toList();

  static bool _isDate(String s) => RegExp(r'^\d{6,8}$').hasMatch(s);

  static bool _usable(String c) =>
      c.isNotEmpty && c != '0' && c.toUpperCase() != 'DEF';

  /// Digits at the end of a code like `GML-418` / `gml_418` -> `418`.
  static String trailingDigits(String raw) {
    final m = RegExp(r'(\d+)$').firstMatch(raw.trim().toEnglishDigits());
    return m == null ? '' : m.group(1)!;
  }

  /// 2.0.170: every code a branch may print on a receipt: branchCode,
  /// storeId and the digits at the end of each (`GML-418` -> `418`).
  /// Upper-cased so `gml-418` == `GML-418`.
  static List<String> codes(BranchModel b) {
    final out = <String>[];
    void add(String raw) {
      final c = raw.trim().toEnglishDigits().toUpperCase();
      if (_usable(c) && !out.contains(c)) out.add(c);
      final d = trailingDigits(c);
      if (_usable(d) && !out.contains(d)) out.add(d);
    }
    add(b.branchCode);
    add(b.receiptSignature?.storeId ?? '');
    return out;
  }

  /// Position of the code counted from the end of the receipt number, read
  /// from the branch pattern. Null when the pattern does not place the code.
  static int? _offsetFromEnd(BranchModel b, String code) {
    final pattern = (b.receiptSignature?.receiptPattern ?? '').trim();
    if (pattern.isEmpty) return null;
    final segs = segments(pattern).map((e) => e.toUpperCase()).toList();
    final i = segs.lastIndexOf(code.toUpperCase());
    if (i < 0) return null;
    return segs.length - 1 - i;
  }

  /// Returns the single branch whose store code appears at its expected
  /// position in [receiptNumber], or null (no match / ambiguous).
  static BranchModel? resolve(String receiptNumber, List<BranchModel> branches) {
    final segs = segments(receiptNumber).map((e) => e.toUpperCase()).toList();
    if (segs.length < 2) return null;
    final hits = <String, BranchModel>{};
    for (final b in branches) {
      for (final code in codes(b)) {
        int? offset = _offsetFromEnd(b, code);
        if (offset == null) {
          if (!_isDate(segs.last)) continue;
          offset = 1;
        }
        final idx = segs.length - 1 - offset;
        if (idx < 0 || idx >= segs.length) continue;
        if (segs[idx] == code) {
          hits[b.id] = b;
          break;
        }
      }
    }
    return hits.length == 1 ? hits.values.first : null;
  }

  /// Store code at the default position (segment before a trailing date).
  static String defaultStoreCode(String receiptNumber) {
    final segs = segments(receiptNumber);
    if (segs.length < 3 || !_isDate(segs.last)) return '';
    final c = segs[segs.length - 2];
    return RegExp(r'^\d{1,6}$').hasMatch(c) ? c : '';
  }

  /// Campaign-level match: a campaign branch id equal to the code or ending
  /// with `_<code>` (branch docs are `<chainId>_<code>`). Unique match only.
  static int? campaignBranchIndex(String receiptNumber, List<String> branchIds) {
    final code = defaultStoreCode(receiptNumber);
    if (code.isEmpty) return null;
    final idx = <int>[];
    for (int i = 0; i < branchIds.length; i++) {
      final id = branchIds[i].trim();
      // 2.0.170: `gomla-market_gml-418` also owns store code `418`.
      final tail = id.contains('_') ? id.substring(id.lastIndexOf('_') + 1) : id;
      if (id == code || id.endsWith('_$code') || trailingDigits(tail) == code) {
        idx.add(i);
      }
    }
    return idx.length == 1 ? idx.first : null;
  }

  /// 2.0.170: campaign branch name for the store code in [receiptNumber],
  /// using the campaign's aligned branchIds/branchNames. Works without any
  /// branch docs (e.g. when loading them timed out). Null when no unique hit.
  static String? campaignBranchName(
    String receiptNumber,
    List<String> branchIds,
    List<String> branchNames,
  ) {
    final i = campaignBranchIndex(receiptNumber, branchIds);
    if (i == null || i >= branchNames.length) return null;
    final n = branchNames[i].trim();
    return n.isEmpty ? null : n;
  }
}
