import '../../features/admin/domain/retail_chain_model.dart';
import '../services/chain_products_intelligence_service.dart';

/// Resolves which retail chain each campaign branch belongs to.
///
/// ID-first: `branchIds[i]` -> branch doc -> `retailChainId`. Name matching is
/// only a fallback for legacy events without branch IDs (or unknown IDs).
/// A name match that resolves to a branch of a chain that is NOT part of the
/// event never attributes the branch to any event chain.
class BranchChainResolver {
  BranchChainResolver._();

  static List<String> splitChainIds(String raw) => raw
      .split(RegExp(r'[,،|]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  static List<String> splitChainNames(String raw) {
    if (raw.trim().isEmpty) return [];
    final parts = raw
        .split(RegExp(r'[•,،|/\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    return parts.isNotEmpty ? parts : [raw.trim()];
  }

  static String cleanBranchName(String s) {
    var str = s.toLowerCase().trim();
    str = str.replaceAll(RegExp(r'[\u064B-\u065F]'), '');
    str = str.replaceAll(RegExp(r'[أإآ]'), 'ا');
    str = str.replaceAll('ة', 'ه');
    str = str.replaceAll('ى', 'ي');
    str = str.replaceAll(RegExp(r'\(.*?\)'), '');
    str = str.replaceAll(RegExp(r'^(فرع|branch|مفرع)\s+'), '');
    str = str.replaceAll(RegExp(r'\s+'), ' ').trim();
    return str;
  }

  static bool isBranchNameMatch(String a, String b) {
    final na = cleanBranchName(a);
    final nb = cleanBranchName(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  static bool _chainNameMatches(String a, String b) {
    final na = a.trim().toLowerCase();
    final nb = b.trim().toLowerCase();
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb || na.contains(nb) || nb.contains(na)) return true;
    final ca = ChainProductsIntelligenceService.normalizeRetailChain(a).toLowerCase();
    final cb = ChainProductsIntelligenceService.normalizeRetailChain(b).toLowerCase();
    if (ca.isEmpty || cb.isEmpty) return false;
    return ca == cb;
  }

  /// Display chain for one branch row. Priority: the branch doc's chain
  /// (looked up by branch id), then the receipt-detected chain, then the
  /// campaign chain ONLY when it names a single chain. Empty when unknown.
  static String resolveBranchDisplayChain({
    String branchDocChain = '',
    String receiptChain = '',
    String campaignChain = '',
  }) {
    String norm(String raw) {
      final r = raw.trim();
      if (r.isEmpty || r == '-' || r == 'غير محدد') return '';
      final n = ChainProductsIntelligenceService.normalizeRetailChain(r);
      return n == 'سلسلة تجارية عامة' ? '' : n;
    }

    for (final c in [branchDocChain, receiptChain]) {
      final n = norm(c);
      if (n.isNotEmpty) return n;
    }
    if (ChainProductsIntelligenceService.detectRetailChains(campaignChain).length <= 1) {
      return norm(campaignChain);
    }
    return '';
  }

  /// Number of distinct branches after merging rows by branch name.
  static int countMergedBranches(Iterable<String> branchNames) =>
      branchNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet().length;

  /// Returns, for each event chain name (in order), the branch labels that
  /// belong to it. Labels are `branchNames[i]` (or the id when no name).
  static Map<String, List<String>> groupBranchesByChain({
    required String retailChainId,
    required String retailChainName,
    required List<String> branchIds,
    required List<String> branchNames,
    required List<BranchModel> dbBranches,
    bool unknownToAllChains = true,
  }) {
    final chainNames = splitChainNames(retailChainName);
    final chainIds = splitChainIds(retailChainId);
    final result = {for (final c in chainNames) c: <String>[]};
    final count = branchIds.length > branchNames.length ? branchIds.length : branchNames.length;
    final labels = <String>[];
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final n = i < branchNames.length ? branchNames[i].trim() : '';
      final id = i < branchIds.length ? branchIds[i].trim() : '';
      final label = n.isNotEmpty ? n : id;
      if (label.isEmpty || labels.contains(label)) continue;
      labels.add(label);
      ids.add(id);
    }
    if (chainNames.isEmpty) return result;
    if (chainNames.length == 1) {
      result[chainNames.first]!.addAll(labels);
      return result;
    }

    // Map an event chain id -> event chain name.
    String? chainNameForId(String chainId, String dbChainName) {
      final cid = chainId.trim().toLowerCase();
      if (cid.isNotEmpty && chainIds.length == chainNames.length) {
        final idx = chainIds.indexWhere((c) => c.toLowerCase() == cid);
        if (idx >= 0) return chainNames[idx];
      }
      if (cid.isNotEmpty && chainIds.isNotEmpty &&
          !chainIds.any((c) => c.toLowerCase() == cid)) {
        return null; // chain outside the event
      }
      for (final c in chainNames) {
        if (_chainNameMatches(c, dbChainName)) return c;
      }
      return null;
    }

    final byId = {for (final b in dbBranches) b.id.trim().toLowerCase(): b};

    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      final id = ids[i].toLowerCase();

      // 1. ID-first
      final dbById = id.isEmpty ? null : byId[id];
      if (dbById != null) {
        final c = chainNameForId(dbById.retailChainId, dbById.retailChainName);
        if (c != null) result[c]!.add(label);
        continue;
      }

      // 2. Legacy fallback: name matching, preferring branches of event chains.
      final candidates =
          dbBranches.where((b) => isBranchNameMatch(label, b.branchName)).toList();
      String? resolved;
      for (final b in candidates) {
        resolved = chainNameForId(b.retailChainId, b.retailChainName);
        if (resolved != null) break;
      }
      if (resolved != null) {
        result[resolved]!.add(label);
        continue;
      }
      if (candidates.isNotEmpty) continue; // belongs to a chain outside the event

      // 3. No DB record: label mentions a chain name?
      final lower = label.toLowerCase();
      final mentioned = chainNames.where((c) {
        final canon = ChainProductsIntelligenceService.normalizeRetailChain(c).toLowerCase();
        return lower.contains(c.toLowerCase()) || (canon.isNotEmpty && lower.contains(canon));
      }).toList();
      if (mentioned.isNotEmpty) {
        result[mentioned.first]!.add(label);
        continue;
      }
      // 4. Unknown: keep the caller's legacy behaviour.
      if (unknownToAllChains) {
        for (final c in chainNames) {
          result[c]!.add(label);
        }
      } else {
        result[chainNames.first]!.add(label);
      }
    }
    return result;
  }
}
