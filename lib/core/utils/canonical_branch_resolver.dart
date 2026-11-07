import '../services/company_gifts_service.dart';
import 'store_code_branch_resolver.dart';

/// One campaign branch, or an explicit refusal to guess.
///
/// Precedence is stored branch id, then a unique store code in the receipt
/// number, then an exact normalized name, then one longest name that is fully
/// contained in the detected text. A shorter sibling is never chosen just
/// because it appears first or because its token is inside a longer name.
class CanonicalBranchMatch {
  final String? id;
  final String name;

  /// True when [id] and [name] are a single campaign branch.
  /// False means callers must keep the stored text and must not assign an id.
  final bool certain;

  const CanonicalBranchMatch({
    required this.id,
    required this.name,
    required this.certain,
  });
}

class CanonicalBranchResolver {
  CanonicalBranchResolver._();

  static const List<String> _areaTokens = [
    'عبور',
    'رحاب',
    'سموحه',
    'ستانلي',
    'جاردينيا',
    'عجمي',
    'محله',
    'تجمع',
    'اكتوبر',
    'منصوره',
    'شبين',
    'منتزه',
    'ميامي',
    'جناكليس',
  ];

  static String norm(String raw) => CompanyGiftsService.normalizeBranchToken(raw);

  /// Campaign name for [detectedRaw], or null when the name is missing,
  /// unknown, or could belong to more than one branch.
  static String? pickCampaignName(String detectedRaw, List<String> campaignNames) {
    final detected = norm(detectedRaw);
    if (detected.isEmpty || campaignNames.isEmpty) return null;

    final norms = <int, String>{};
    for (var i = 0; i < campaignNames.length; i++) {
      final n = norm(campaignNames[i]);
      if (n.isNotEmpty) norms[i] = n;
    }
    if (norms.isEmpty) return null;

    final exact = norms.entries.where((e) => e.value == detected).toList();
    if (exact.length == 1) return campaignNames[exact.first.key];
    if (exact.length > 1) return null;

    final contained = norms.entries.where((e) => detected.contains(e.value)).toList();
    if (contained.isNotEmpty) {
      contained.sort((a, b) => b.value.length.compareTo(a.value.length));
      final longestLen = contained.first.value.length;
      final top = contained.where((e) => e.value.length == longestLen).toList();
      if (top.length == 1) {
        final winner = top.first.value;
        final longerSiblingLeftOut = norms.values.any(
          (n) => n.length > winner.length && _isTokenPrefix(winner, n) && !detected.contains(n),
        );
        if (!longerSiblingLeftOut) return campaignNames[top.first.key];
      }
    }

    return _uniqueArea(detected, norms, campaignNames);
  }

  /// True when the detected text shares a normalized token with any candidate.
  /// Used only to tell "no such branch" from "two branches still possible".
  static bool hasAnyNameOverlap(String detectedRaw, List<String> campaignNames) {
    final detected = norm(detectedRaw);
    if (detected.isEmpty) return false;
    for (final name in campaignNames) {
      final n = norm(name);
      if (n.isEmpty) continue;
      if (n == detected || detected.contains(n) || n.contains(detected)) return true;
    }
    return false;
  }

  static bool _isTokenPrefix(String short, String longer) {
    if (!longer.startsWith(short) || longer.length <= short.length) return false;
    return longer.substring(short.length).startsWith(' ');
  }

  static String? _uniqueArea(
    String detected,
    Map<int, String> norms,
    List<String> campaignNames,
  ) {
    final hits = <int>{};
    for (final token in _areaTokens) {
      if (!detected.contains(token)) continue;
      for (final entry in norms.entries) {
        if (entry.value.contains(token)) hits.add(entry.key);
      }
    }
    if (hits.length != 1) return null;
    return campaignNames[hits.first];
  }

  /// Resolves a receipt or a stored row onto one campaign branch.
  ///
  /// [branchId] is the id already stored on the row. When it is one of
  /// [branchIds], that id wins over a conflicting detected name. An id that
  /// is not in this campaign is left untouched and [certain] stays false.
  /// A store code that belongs to more than one id (two chains, same digits)
  /// does not select either branch.
  static CanonicalBranchMatch resolve({
    required List<String> branchIds,
    required List<String> branchNames,
    String branchId = '',
    String detectedName = '',
    String receiptNumber = '',
  }) {
    final detected = detectedName.trim();
    final storedId = branchId.trim();

    if (storedId.isNotEmpty) {
      final i = branchIds.indexOf(storedId);
      if (i >= 0) {
        final name = i < branchNames.length && branchNames[i].trim().isNotEmpty
            ? branchNames[i].trim()
            : detected;
        return CanonicalBranchMatch(id: branchIds[i], name: name, certain: true);
      }
      return CanonicalBranchMatch(id: storedId, name: detected, certain: false);
    }

    if (branchIds.isEmpty && branchNames.isEmpty) {
      return CanonicalBranchMatch(id: null, name: detected, certain: false);
    }

    final codeIndex = StoreCodeBranchResolver.campaignBranchIndex(receiptNumber, branchIds);
    if (codeIndex != null && codeIndex < branchIds.length) {
      final name = codeIndex < branchNames.length && branchNames[codeIndex].trim().isNotEmpty
          ? branchNames[codeIndex].trim()
          : detected;
      return CanonicalBranchMatch(id: branchIds[codeIndex], name: name, certain: true);
    }

    final picked = pickCampaignName(detected, branchNames);
    if (picked != null) {
      final i = branchNames.indexOf(picked);
      final id = i >= 0 && i < branchIds.length && branchIds[i].trim().isNotEmpty
          ? branchIds[i]
          : null;
      return CanonicalBranchMatch(id: id, name: picked, certain: true);
    }

    return CanonicalBranchMatch(id: null, name: detected, certain: false);
  }
}
