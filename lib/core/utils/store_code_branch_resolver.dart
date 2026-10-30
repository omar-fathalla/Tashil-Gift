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

  static String _code(BranchModel b) {
    final c = b.branchCode.trim().toEnglishDigits();
    if (c.isNotEmpty && c != '0' && c.toUpperCase() != 'DEF') return c;
    final s = (b.receiptSignature?.storeId ?? '').trim().toEnglishDigits();
    return (s.isNotEmpty && s != '0') ? s : '';
  }

  /// Position of the code counted from the end of the receipt number, read
  /// from the branch pattern. Null when the pattern does not place the code.
  static int? _offsetFromEnd(BranchModel b, String code) {
    final pattern = (b.receiptSignature?.receiptPattern ?? '').trim();
    if (pattern.isEmpty) return null;
    final segs = segments(pattern);
    final i = segs.lastIndexOf(code);
    if (i < 0) return null;
    return segs.length - 1 - i;
  }

  /// Returns the single branch whose store code appears at its expected
  /// position in [receiptNumber], or null (no match / ambiguous).
  static BranchModel? resolve(String receiptNumber, List<BranchModel> branches) {
    final segs = segments(receiptNumber);
    if (segs.length < 2) return null;
    final hits = <String, BranchModel>{};
    for (final b in branches) {
      final code = _code(b);
      if (code.isEmpty) continue;
      int? offset = _offsetFromEnd(b, code);
      if (offset == null) {
        if (!_isDate(segs.last)) continue;
        offset = 1;
      }
      final idx = segs.length - 1 - offset;
      if (idx < 0 || idx >= segs.length) continue;
      if (segs[idx] == code) hits[b.id] = b;
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
      if (id == code || id.endsWith('_$code')) idx.add(i);
    }
    return idx.length == 1 ? idx.first : null;
  }
}
