import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
import 'chain_products_intelligence_service.dart';
import '../utils/arabic_numbers_utils.dart';
import '../../features/admin/domain/retail_chain_model.dart';

final retailChainsServiceProvider = Provider<RetailChainsService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return RetailChainsService(firestore);
});

class RetailChainsService {
  final FirebaseFirestore _firestore;

  RetailChainsService(this._firestore);

  CollectionReference<Map<String, dynamic>> get _chainsCollection =>
      _firestore.collection('retail_chains');

  CollectionReference<Map<String, dynamic>> get _branchesCollection =>
      _firestore.collection('branches');

  // --- DEDUPLICATION HELPERS ---

  /// Sanitizes a list of branches by removing any duplicate records in memory.
  /// Precedence is given to records with rich AI POS signatures or newer timestamps.
  List<BranchModel> _deduplicateBranchList(List<BranchModel> rawList) {
    final Map<String, BranchModel> uniqueMap = {};

    for (final branch in rawList) {
      final chainId = branch.retailChainId.trim().toLowerCase();
      final cleanCode = branch.branchCode.trim().toLowerCase().toEnglishDigits();
      final cleanName = branch.branchName.trim().toLowerCase();
      final storeId = branch.receiptSignature?.storeId.trim().toLowerCase().toEnglishDigits() ?? '';

      // Determine deduplication composite key
      String primaryKey;
      if (cleanCode.isNotEmpty && cleanCode != 'DEF' && cleanCode != '0') {
        primaryKey = '$chainId:code:$cleanCode';
      } else if (storeId.isNotEmpty) {
        primaryKey = '$chainId:store:$storeId';
      } else {
        primaryKey = '$chainId:name:$cleanName';
      }

      if (!uniqueMap.containsKey(primaryKey)) {
        uniqueMap[primaryKey] = branch;
      } else {
        final existing = uniqueMap[primaryKey]!;
        // Prefer branch with receiptSignature, or newer record
        final existingHasSig = existing.receiptSignature != null;
        final currentHasSig = branch.receiptSignature != null;

        if (!existingHasSig && currentHasSig) {
          uniqueMap[primaryKey] = branch;
        } else if (existingHasSig == currentHasSig) {
          final existingTime = existing.createdAt ?? DateTime(2000);
          final currentTime = branch.createdAt ?? DateTime(2000);
          if (currentTime.isAfter(existingTime)) {
            uniqueMap[primaryKey] = branch;
          }
        }
      }
    }

    final result = uniqueMap.values.toList();
    result.sort((a, b) => a.branchName.compareTo(b.branchName));
    return result;
  }

  // --- RETAIL CHAINS STREAMS & QUERIES ---

  Stream<List<RetailChainModel>> getRetailChainsStream() {
    return _chainsCollection
        .snapshots()
        .map((snapshot) {
          final Map<String, RetailChainModel> uniqueChains = {};
          for (final doc in snapshot.docs) {
            final chain = RetailChainModel.fromFirestore(doc);
            final key = chain.slug.trim().toLowerCase().isNotEmpty
                ? chain.slug.trim().toLowerCase()
                : chain.name.trim().toLowerCase();
            if (!uniqueChains.containsKey(key)) {
              uniqueChains[key] = chain;
            }
          }
          final list = uniqueChains.values.toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          return list;
        });
  }

  Future<List<RetailChainModel>> getRetailChains() async {
    final snapshot = await _chainsCollection.get();
    final Map<String, RetailChainModel> uniqueChains = {};
    for (final doc in snapshot.docs) {
      final chain = RetailChainModel.fromFirestore(doc);
      final key = chain.slug.trim().toLowerCase().isNotEmpty
          ? chain.slug.trim().toLowerCase()
          : chain.name.trim().toLowerCase();
      if (!uniqueChains.containsKey(key)) {
        uniqueChains[key] = chain;
      }
    }
    final list = uniqueChains.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Adds a new retail chain.
  /// Returns `true` if duplicate was detected and addition was rejected.
  /// Returns `false` on successful addition of new unique chain.
  Future<bool> addRetailChain(RetailChainModel chain) async {
    final cleanSlug = chain.slug.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');
    final deterministicId = cleanSlug.isNotEmpty ? cleanSlug : chain.name.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');
    
    // Check if chain already exists by slug or name
    final existingChains = await getRetailChains();
    final existing = existingChains.where((c) =>
        c.id == deterministicId ||
        c.slug.toLowerCase() == cleanSlug ||
        c.name.trim().toLowerCase() == chain.name.trim().toLowerCase()
    ).firstOrNull;

    if (existing != null) {
      // Reject duplicate creation
      return true;
    }

    final docId = deterministicId.isNotEmpty ? deterministicId : _chainsCollection.doc().id;
    final docRef = _chainsCollection.doc(docId);
    
    final toSave = chain.copyWith(
      id: docId,
      slug: cleanSlug.isNotEmpty ? cleanSlug : docId,
      createdAt: chain.createdAt ?? DateTime.now(),
    );

    await docRef.set(toSave.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    return false;
  }

  Future<void> updateRetailChain(RetailChainModel chain) async {
    final cleanSlug = chain.slug.toLowerCase().trim().toEnglishDigits();
    await _chainsCollection.doc(chain.id).set(
      chain.copyWith(slug: cleanSlug).toFirestore(),
      SetOptions(merge: true),
    ).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
  }

  Future<void> deleteRetailChain(String chainId) async {
    // Delete all branches associated with this chain
    final branchesSnap = await _branchesCollection.where('retailChainId', isEqualTo: chainId).get();
    final batch = _firestore.batch();
    
    for (final doc in branchesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_chainsCollection.doc(chainId));

    await batch.commit().timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
  }

  // --- BRANCHES STREAMS & QUERIES ---

  Stream<List<BranchModel>> getBranchesStreamForChain(String retailChainId) {
    if (retailChainId.trim().isEmpty) {
      return Stream.value([]);
    }
    return _branchesCollection
        .where('retailChainId', isEqualTo: retailChainId)
        .snapshots()
        .map((snapshot) {
          final rawList = snapshot.docs
              .map((doc) => BranchModel.fromFirestore(doc))
              .toList();
          return _deduplicateBranchList(rawList);
        });
  }

  Future<List<BranchModel>> getBranchesForChain(String retailChainId) async {
    if (retailChainId.trim().isEmpty) return [];
    final chainIds = retailChainId
        .split(RegExp(r'[,،]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (chainIds.isEmpty) return [];
    if (chainIds.length == 1) {
      final snapshot = await _branchesCollection
          .where('retailChainId', isEqualTo: chainIds.first)
          .get();
      final rawList = snapshot.docs
          .map((doc) => BranchModel.fromFirestore(doc))
          .toList();
      return _deduplicateBranchList(rawList);
    }
    final allBranches = await getAllBranches();
    final filtered = allBranches.where((b) {
      final bChain = b.retailChainId.trim().toLowerCase();
      return chainIds.any((cid) => cid.toLowerCase() == bChain);
    }).toList();
    return _deduplicateBranchList(filtered);
  }

  /// Fetches all branches matching the event's chains, branch IDs, and branch names with their POS signatures.
  /// 2.0.170: loads only the given campaign branch docs (a few small doc
  /// reads) instead of the whole `branches` collection. With no ids, falls
  /// back to the campaign's chains (all-branches campaigns). Throws on a
  /// read failure so callers can retry and log instead of silently
  /// continuing with an empty list.
  Future<List<BranchModel>> getCampaignBranches({
    List<String> branchIds = const [],
    String retailChainId = '',
  }) async {
    final ids = branchIds.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    if (ids.isNotEmpty) {
      final snaps = await Future.wait(ids.map((id) => _branchesCollection.doc(id).get()));
      final found = [
        for (final d in snaps)
          if (d.exists) BranchModel.fromFirestore(d),
      ];
      if (found.isNotEmpty) return _deduplicateBranchList(found);
    }
    final chainIds = retailChainId
        .split(RegExp(r'[,،]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (chainIds.isEmpty) return const [];
    final out = <BranchModel>[];
    for (int i = 0; i < chainIds.length; i += 30) {
      final chunk = chainIds.sublist(i, math.min(i + 30, chainIds.length));
      final q = await _branchesCollection.where('retailChainId', whereIn: chunk).get();
      out.addAll(q.docs.map((d) => BranchModel.fromFirestore(d)));
    }
    return _deduplicateBranchList(out);
  }

  Future<List<BranchModel>> getBranchesForEvent({
    String retailChainId = '',
    List<String> branchIds = const [],
    List<String> branchNames = const [],
  }) async {
    final allBranches = await getAllBranches();
    if (allBranches.isEmpty) return [];

    final cleanChainIds = retailChainId
        .split(RegExp(r'[,،]'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final cleanBranchIds = branchIds.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
    final cleanBranchNames = branchNames.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();

    if (cleanChainIds.isEmpty && cleanBranchIds.isEmpty && cleanBranchNames.isEmpty) {
      return allBranches;
    }

    final filtered = allBranches.where((b) {
      final bId = b.id.trim().toLowerCase();
      final bName = b.branchName.trim().toLowerCase();
      final bChain = b.retailChainId.trim().toLowerCase();
      
      if (cleanBranchIds.contains(bId)) return true;
      if (cleanBranchNames.contains(bName)) return true;
      if (cleanChainIds.contains(bChain)) return true;
      return false;
    }).toList();

    return _deduplicateBranchList(filtered.isNotEmpty ? filtered : allBranches);
  }

  Stream<List<BranchModel>> getAllBranchesStream() {
    return _branchesCollection
        .snapshots()
        .map((snapshot) {
          final rawList = snapshot.docs
              .map((doc) => BranchModel.fromFirestore(doc))
              .toList();
          return _deduplicateBranchList(rawList);
        });
  }

  Future<List<BranchModel>> getAllBranches() async {
    final snapshot = await _branchesCollection.get();
    final rawList = snapshot.docs
        .map((doc) => BranchModel.fromFirestore(doc))
        .toList();
    return _deduplicateBranchList(rawList);
  }

  /// Adds a branch with strict deduplication validation.
  /// If a branch with the same code, name, or storeId already exists in this chain,
  /// the addition is rejected (returns `true` for isDuplicate) and no duplicate doc is created.
  Future<bool> addBranch(BranchModel branch) async {
    final chainId = branch.retailChainId.trim().toLowerCase();
    final cleanCode = branch.branchCode.trim().toUpperCase().toEnglishDigits();
    final cleanName = branch.branchName.trim().toLowerCase();
    final storeId = branch.receiptSignature?.storeId.trim().toEnglishDigits() ?? '';

    // Check for existing branch in the same chain
    final existingBranchesSnap = await _branchesCollection
        .where('retailChainId', isEqualTo: branch.retailChainId)
        .get();

    for (final doc in existingBranchesSnap.docs) {
      final data = doc.data();
      final existingCode = (data['branchCode']?.toString() ?? '').trim().toUpperCase().toEnglishDigits();
      final existingName = (data['branchName']?.toString() ?? '').trim().toLowerCase();
      final sigMap = data['receiptSignature'] as Map<String, dynamic>?;
      final existingStoreId = (sigMap?['storeId']?.toString() ?? '').trim().toEnglishDigits();

      final matchesCode = cleanCode.isNotEmpty && cleanCode != 'DEF' && cleanCode != '0' && existingCode == cleanCode;
      final matchesStoreId = storeId.isNotEmpty && existingStoreId.isNotEmpty && existingStoreId == storeId;
      final matchesName = cleanName.isNotEmpty && existingName == cleanName;

      if (matchesCode || matchesStoreId || matchesName) {
        // Reject duplicate addition
        return true;
      }
    }

    // Deterministic ID for new branch
    final deterministicDocId = branch.id.isNotEmpty
        ? branch.id
        : '${chainId}_${cleanCode.isNotEmpty ? cleanCode.toLowerCase() : cleanName.replaceAll(RegExp(r'\s+'), '_')}';

    final docRef = _branchesCollection.doc(deterministicDocId);

    final toSave = branch.copyWith(
      id: docRef.id,
      branchCode: cleanCode,
      createdAt: branch.createdAt ?? DateTime.now(),
    );

    await docRef.set(toSave.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    // Update branches count in parent chain
    await _recalculateChainBranchesCount(branch.retailChainId);

    return false;
  }

  /// Finds an existing registered branch matching by code, storeId, or branch name.
  Future<BranchModel?> findMatchingBranch(BranchModel branch) async {
    final cleanCode = branch.branchCode.trim().toUpperCase().toEnglishDigits();
    final cleanName = branch.branchName.trim().toLowerCase();
    final storeId = branch.receiptSignature?.storeId.trim().toEnglishDigits() ?? '';

    final existingBranchesSnap = await _branchesCollection
        .where('retailChainId', isEqualTo: branch.retailChainId)
        .get();

    for (final doc in existingBranchesSnap.docs) {
      final data = doc.data();
      final existingCode = (data['branchCode']?.toString() ?? '').trim().toUpperCase().toEnglishDigits();
      final existingName = (data['branchName']?.toString() ?? '').trim().toLowerCase();
      final sigMap = data['receiptSignature'] as Map<String, dynamic>?;
      final existingStoreId = (sigMap?['storeId']?.toString() ?? '').trim().toEnglishDigits();

      final matchesCode = cleanCode.isNotEmpty && cleanCode != 'DEF' && cleanCode != '0' && existingCode == cleanCode;
      final matchesStoreId = storeId.isNotEmpty && existingStoreId.isNotEmpty && existingStoreId == storeId;
      final matchesName = cleanName.isNotEmpty && existingName == cleanName;

      if (matchesCode || matchesStoreId || matchesName) {
        return BranchModel.fromFirestore(doc);
      }
    }
    return null;
  }

  /// Adds or updates (upserts) a branch with smart receipt signature merging.
  /// If a branch with matching code, storeId, or name exists in the chain, it is updated
  /// with the new AI signature and details without duplicating records.
  /// Returns `true` if an existing branch was updated, and `false` if newly created.
  Future<bool> upsertBranch(BranchModel branch) async {
    final chainId = branch.retailChainId.trim().toLowerCase();
    final cleanCode = branch.branchCode.trim().toUpperCase().toEnglishDigits();
    final cleanName = branch.branchName.trim().toLowerCase();
    final storeId = branch.receiptSignature?.storeId.trim().toEnglishDigits() ?? '';

    // Check for existing branch in the same chain
    final existingBranchesSnap = await _branchesCollection
        .where('retailChainId', isEqualTo: branch.retailChainId)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    for (final doc in existingBranchesSnap.docs) {
      final data = doc.data();
      final existingCode = (data['branchCode']?.toString() ?? '').trim().toUpperCase().toEnglishDigits();
      final existingName = (data['branchName']?.toString() ?? '').trim().toLowerCase();
      final sigMap = data['receiptSignature'] as Map<String, dynamic>?;
      final existingStoreId = (sigMap?['storeId']?.toString() ?? '').trim().toEnglishDigits();

      final matchesCode = cleanCode.isNotEmpty && cleanCode != 'DEF' && cleanCode != '0' && existingCode == cleanCode;
      final matchesStoreId = storeId.isNotEmpty && existingStoreId.isNotEmpty && existingStoreId == storeId;
      final matchesName = cleanName.isNotEmpty && existingName == cleanName;

      if (matchesCode || matchesStoreId || matchesName) {
        existingDoc = doc;
        break;
      }
    }

    if (existingDoc != null) {
      final existingData = existingDoc.data() ?? {};
      final mergedBranch = branch.copyWith(
        id: existingDoc.id,
        branchCode: cleanCode.isNotEmpty ? cleanCode : (existingData['branchCode']?.toString() ?? ''),
        city: branch.city.isNotEmpty ? branch.city : (existingData['city']?.toString() ?? ''),
        address: branch.address.isNotEmpty ? branch.address : (existingData['address']?.toString() ?? ''),
      );
      await _branchesCollection.doc(existingDoc.id).set(
        mergedBranch.toFirestore(),
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 4), onTimeout: () {});
      await _recalculateChainBranchesCount(branch.retailChainId);
      return true; // updated
    }

    // Deterministic ID for new branch
    final deterministicDocId = branch.id.isNotEmpty
        ? branch.id
        : '${chainId}_${cleanCode.isNotEmpty ? cleanCode.toLowerCase() : cleanName.replaceAll(RegExp(r'\s+'), '_')}';

    final docRef = _branchesCollection.doc(deterministicDocId);
    final toSave = branch.copyWith(
      id: docRef.id,
      branchCode: cleanCode,
      createdAt: branch.createdAt ?? DateTime.now(),
    );

    await docRef.set(toSave.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    await _recalculateChainBranchesCount(branch.retailChainId);
    return false; // newly created
  }

  Future<void> updateBranch(BranchModel branch) async {
    final cleanCode = branch.branchCode.trim().toUpperCase().toEnglishDigits();
    await _branchesCollection.doc(branch.id).set(
      branch.copyWith(branchCode: cleanCode).toFirestore(),
      SetOptions(merge: true),
    ).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
  }

  Future<void> deleteBranch(String branchId, String retailChainId) async {
    await _branchesCollection.doc(branchId).delete().timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    await _recalculateChainBranchesCount(retailChainId);
  }

  Future<void> _recalculateChainBranchesCount(String retailChainId) async {
    if (retailChainId.trim().isEmpty) return;
    try {
      final snap = await _branchesCollection
          .where('retailChainId', isEqualTo: retailChainId)
          .get();
      final uniqueBranches = _deduplicateBranchList(
        snap.docs.map((d) => BranchModel.fromFirestore(d)).toList(),
      );
      await _chainsCollection.doc(retailChainId).set({
        'branchesCount': uniqueBranches.length,
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  /// System-wide cleanup: Scans all branches in Firestore, identifies duplicate documents,
  /// merges data into one canonical document, and deletes redundant duplicate documents.
  Future<int> deduplicateAllBranchesInFirestore() async {
    try {
      final snapshot = await _branchesCollection.get();
      final Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> grouped = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final chainId = (data['retailChainId']?.toString() ?? '').trim().toLowerCase();
        final cleanCode = (data['branchCode']?.toString() ?? '').trim().toUpperCase().toEnglishDigits();
        final cleanName = (data['branchName']?.toString() ?? '').trim().toLowerCase();
        final sigMap = data['receiptSignature'] as Map<String, dynamic>?;
        final storeId = (sigMap?['storeId']?.toString() ?? '').trim().toEnglishDigits();

        String primaryKey;
        if (cleanCode.isNotEmpty && cleanCode != 'DEF' && cleanCode != '0') {
          primaryKey = '$chainId:code:$cleanCode';
        } else if (storeId.isNotEmpty) {
          primaryKey = '$chainId:store:$storeId';
        } else {
          primaryKey = '$chainId:name:$cleanName';
        }

        grouped.putIfAbsent(primaryKey, () => []).add(doc);
      }

      final batch = _firestore.batch();
      int deletedDuplicates = 0;
      final Set<String> affectedChains = {};

      for (final entry in grouped.entries) {
        final docList = entry.value;
        if (docList.length > 1) {
          // Sort to find the richest document
          docList.sort((a, b) {
            final aSig = a.data()?['receiptSignature'] != null ? 1 : 0;
            final bSig = b.data()?['receiptSignature'] != null ? 1 : 0;
            if (aSig != bSig) return bSig.compareTo(aSig); // Prefer doc with signature
            return b.id.compareTo(a.id);
          });

          // Keep docList.first, delete the rest
          for (int i = 1; i < docList.length; i++) {
            batch.delete(docList[i].reference);
            deletedDuplicates++;
            final chainId = docList[i].data()?['retailChainId']?.toString() ?? '';
            if (chainId.isNotEmpty) affectedChains.add(chainId);
          }
        }
      }

      if (deletedDuplicates > 0) {
        await batch.commit().timeout(
          const Duration(seconds: 6),
          onTimeout: () {},
        );

        // Recalculate for affected chains
        for (final chainId in affectedChains) {
          await _recalculateChainBranchesCount(chainId);
        }
      }

      return deletedDuplicates;
    } catch (_) {
      return 0;
    }
  }

  // --- PRE-SEEDED FAMOUS CHAINS & BRANCHES INITIALIZATION ---

  Future<int> seedPredefinedRetailChains() async {
    final predefinedData = <String, Map<String, dynamic>>{
      'fathalla': {
        'name': 'أسواق فتح الله',
        'slug': 'fathalla',
        'branches': [
          {'name': 'فرع سموحة', 'city': 'الإسكندرية', 'code': 'FAT-SMH'},
          {'name': 'فرع الهانوفيل', 'city': 'الإسكندرية (العجمي)', 'code': 'FAT-HNF'},
          {'name': 'فرع عجمي ستار', 'city': 'الإسكندرية (العجمي)', 'code': 'FAT-AGM'},
          {'name': 'فرع كفر الدوار', 'city': 'البحيرة', 'code': 'FAT-KFR'},
          {'name': 'فرع لوران', 'city': 'الإسكندرية', 'code': 'FAT-LRN'},
          {'name': 'فرع جناكليس', 'city': 'الإسكندرية', 'code': 'FAT-JNK'},
          {'name': 'فرع السيوف', 'city': 'الإسكندرية', 'code': 'FAT-SYF'},
          {'name': 'فرع ميامي', 'city': 'الإسكندرية', 'code': 'FAT-MIA'},
          {'name': 'فرع العصافرة', 'city': 'الإسكندرية', 'code': 'FAT-ASF'},
          {'name': 'فرع محرم بك', 'city': 'الإسكندرية', 'code': 'FAT-MHR'},
        ],
      },
      'carrefour': {
        'name': 'كارفور مصر',
        'slug': 'carrefour',
        'branches': [
          {'name': 'فرع سيتي سنتر الإسكندرية', 'city': 'الإسكندرية', 'code': 'CRF-ALX'},
          {'name': 'فرع سيتي سنتر المعادي', 'city': 'القاهرة', 'code': 'CRF-MAD'},
          {'name': 'فرع مول مصر', 'city': 'الجيزة (6 أكتوبر)', 'code': 'CRF-MOE'},
          {'name': 'فرع مول العرب', 'city': 'الجيزة (6 أكتوبر)', 'code': 'CRF-MOA'},
          {'name': 'فرع سيتي سنتر ألماظة', 'city': 'القاهرة', 'code': 'CRF-ALM'},
          {'name': 'فرع مدينتي', 'city': 'القاهرة', 'code': 'CRF-MDN'},
          {'name': 'فرع الشروق', 'city': 'القاهرة', 'code': 'CRF-SHR'},
          {'name': 'فرع داندي مول', 'city': 'الجيزة', 'code': 'CRF-DND'},
        ],
      },
      'spinneys': {
        'name': 'سبينس',
        'slug': 'spinneys',
        'branches': [
          {'name': 'فرع سان ستيفانو', 'city': 'الإسكندرية', 'code': 'SPN-SAN'},
          {'name': 'فرع مول العرب', 'city': 'الجيزة (6 أكتوبر)', 'code': 'SPN-MOA'},
          {'name': 'فرع سيتي سكيب مول', 'city': 'الجيزة (6 أكتوبر)', 'code': 'SPN-CTY'},
          {'name': 'فرع أرينا مول', 'city': 'القاهرة (التجمع الخامس)', 'code': 'SPN-ARN'},
          {'name': 'فرع جراندا الشروق', 'city': 'القاهرة (الشروق)', 'code': 'SPN-GRN'},
        ],
      },
      'seoudi': {
        'name': 'سعودي ماركت',
        'slug': 'seoudi',
        'branches': [
          {'name': 'فرع الشيخ زايد (هايبر ون)', 'city': 'الجيزة (الشيخ زايد)', 'code': 'SOD-ZYD'},
          {'name': 'فرع الدقي (مصدق)', 'city': 'الجيزة', 'code': 'SOD-DQK'},
          {'name': 'فرع المهندسين (لبنان)', 'city': 'الجيزة', 'code': 'SOD-MHD'},
          {'name': 'فرع المعادي (اللاسلكي)', 'city': 'القاهرة', 'code': 'SOD-MAD'},
          {'name': 'فرع التجمع الخامس (الواتر واي)', 'city': 'القاهرة', 'code': 'SOD-TGM'},
        ],
      },
      'zahran': {
        'name': 'زهران ماركت',
        'slug': 'zahran',
        'branches': [
          {'name': 'فرع كفر عبده', 'city': 'الإسكندرية', 'code': 'ZAH-KFR'},
          {'name': 'فرع رشدي', 'city': 'الإسكندرية', 'code': 'ZAH-RSH'},
          {'name': 'فرع ستانلي', 'city': 'الإسكندرية', 'code': 'ZAH-STN'},
          {'name': 'فرع الساحل الشمالي (مارينا)', 'city': 'الساحل الشمالي', 'code': 'ZAH-MRN'},
          {'name': 'فرع سموحة (جرين بلازا)', 'city': 'الإسكندرية', 'code': 'ZAH-SMH'},
        ],
      },
      'beit-elgomla': {
        'name': 'بيت الجملة',
        'slug': 'beit-elgomla',
        'branches': [
          {'name': 'فرع العصافرة', 'city': 'الإسكندرية', 'code': 'BGM-ASF'},
          {'name': 'فرع فيكتوريا', 'city': 'الإسكندرية', 'code': 'BGM-VCT'},
          {'name': 'فرع المندرة', 'city': 'الإسكندرية', 'code': 'BGM-MND'},
          {'name': 'فرع سيدي بشر', 'city': 'الإسكندرية', 'code': 'BGM-SDB'},
        ],
      },
      'gomla-market': {
        'name': 'جملة ماركت',
        'slug': 'gomla-market',
        'branches': [
          {'name': 'فرع سيدي جابر', 'city': 'الإسكندرية', 'code': 'GML-SDJ'},
          {'name': 'فرع لوران', 'city': 'الإسكندرية', 'code': 'GML-LRN'},
          {'name': 'فرع الشاطبي', 'city': 'الإسكندرية', 'code': 'GML-SHT'},
        ],
      },
    };

    final batch = _firestore.batch();
    int addedCount = 0;

    for (final entry in predefinedData.entries) {
      final slug = entry.key;
      final chainData = entry.value;
      final chainName = chainData['name'] as String;
      final branchesList = chainData['branches'] as List<Map<String, String>>;

      final chainDocRef = _chainsCollection.doc(slug);
      batch.set(chainDocRef, {
        'name': chainName,
        'slug': slug,
        'branchesCount': branchesList.length,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (final b in branchesList) {
        final branchDocRef = _branchesCollection.doc('$slug-${b['code']!.toLowerCase()}');
        batch.set(branchDocRef, {
          'retailChainId': slug,
          'retailChainName': chainName,
          'branchName': b['name']!,
          'city': b['city']!,
          'branchCode': b['code']!,
          'address': '',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        addedCount++;
      }
    }

    await batch.commit().timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );

    return addedCount;
  }

  // --- AUTOMATED BRANCH ENRICHMENT & MERGE GOVERNANCE ---

  static String _normalizeBranchSearchToken(String s) {
    var str = s.trim().toLowerCase();
    // Strip parentheticals like (القاهرة), (الإسكندرية), (الجيزة), etc.
    str = str.replaceAll(RegExp(r'\(.*?\)'), ' ');
    // Strip common store prefixes
    str = str.replaceAll(RegExp(r'^(?:فرع|هايبر|سوبر|ماركت|اسواق|أسواق|مجمع)\s+'), '');
    // Normalize Arabic characters
    str = str
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return str;
  }

  /// Finds an existing branch that matches the detected chain and branch name (or direct branchId),
  /// checks if the branch is missing any metadata (storeId, posNumber, taxNumber, address, hotline),
  /// and if so, writes a pendingEnrichment proposal to the branch document in Firestore.
  Future<bool> stageBranchEnrichment({
    String branchId = '',
    required String chainName,
    required String branchName,
    required String storeId,
    required String posNumber,
    required String taxNumber,
    required String commercialReg,
    required String hotline,
    required String branchAddress,
    required String receiptNumber,
    required String receiptDate,
    String sourceReceiptUrl = '',
  }) async {
    final cleanChain = chainName.trim();
    final cleanBranch = branchName.trim();
    if (branchId.isEmpty && cleanChain.isEmpty && cleanBranch.isEmpty) return false;

    // Check if at least one actionable field was extracted
    final hasHarvestedData = storeId.trim().isNotEmpty ||
        posNumber.trim().isNotEmpty ||
        taxNumber.trim().isNotEmpty ||
        commercialReg.trim().isNotEmpty ||
        hotline.trim().isNotEmpty ||
        branchAddress.trim().isNotEmpty;
    if (!hasHarvestedData) return false;

    BranchModel? matchedBranch;

    // 1. Direct branchId lookup if provided
    if (branchId.trim().isNotEmpty) {
      final doc = await _branchesCollection.doc(branchId.trim()).get();
      if (doc.exists) {
        matchedBranch = BranchModel.fromFirestore(doc);
      }
    }

    // 2. Fuzzy match across all branches if not matched by ID
    if (matchedBranch == null) {
      final branches = await getAllBranches();
      final canonicalChain = ChainProductsIntelligenceService.normalizeRetailChain(cleanChain);
      final detBranchNorm = _normalizeBranchSearchToken(cleanBranch);

      for (final b in branches) {
        final bCanonicalChain = ChainProductsIntelligenceService.normalizeRetailChain(b.retailChainName);
        final bBranchNorm = _normalizeBranchSearchToken(b.branchName);

        final bool chainMatches = canonicalChain.isEmpty ||
            bCanonicalChain.isEmpty ||
            canonicalChain.toLowerCase() == bCanonicalChain.toLowerCase() ||
            cleanChain.toLowerCase().contains(b.retailChainName.toLowerCase()) ||
            b.retailChainName.toLowerCase().contains(cleanChain.toLowerCase());

        final bool branchMatches = detBranchNorm.isNotEmpty &&
            bBranchNorm.isNotEmpty &&
            (detBranchNorm == bBranchNorm ||
                detBranchNorm.contains(bBranchNorm) ||
                bBranchNorm.contains(detBranchNorm));

        if (chainMatches && branchMatches) {
          matchedBranch = b;
          break;
        }
      }
    }

    if (matchedBranch == null) return false;

    // Check if the branch actually misses any of these data points
    final existingSig = matchedBranch.receiptSignature;
    final bool missingStoreId = (matchedBranch.branchCode.isEmpty || matchedBranch.branchCode == 'DEF') &&
        (existingSig == null || existingSig.storeId.isEmpty) &&
        storeId.trim().isNotEmpty;
    final bool missingPos = (existingSig == null || existingSig.posNumberPattern.isEmpty) && posNumber.trim().isNotEmpty;
    final bool missingTax = (existingSig == null || existingSig.taxNumber.isEmpty) && taxNumber.trim().isNotEmpty;
    final bool missingComm = (existingSig == null || existingSig.commercialReg.isEmpty) && commercialReg.trim().isNotEmpty;
    final bool missingHotline = (existingSig == null || existingSig.hotline.isEmpty) && hotline.trim().isNotEmpty;
    final bool missingAddress = matchedBranch.address.isEmpty && branchAddress.trim().isNotEmpty;

    final bool hasNewData = missingStoreId || missingPos || missingTax || missingComm || missingHotline || missingAddress;
    if (!hasNewData) return false;

    final enrichment = BranchPendingEnrichment(
      storeId: storeId.trim(),
      posNumber: posNumber.trim(),
      taxNumber: taxNumber.trim(),
      commercialReg: commercialReg.trim(),
      hotline: hotline.trim(),
      branchAddress: branchAddress.trim(),
      receiptNumber: receiptNumber.trim(),
      receiptDate: receiptDate.trim(),
      // 2.0.170: never store inline base64 images on branch docs (they made
      // every branch read megabytes); only real URLs are kept.
      sourceReceiptUrl: sourceReceiptUrl.trim().startsWith('data:') ? '' : sourceReceiptUrl.trim(),
      detectedAt: DateTime.now(),
    );

    await _branchesCollection.doc(matchedBranch.id).set({
      'pendingEnrichment': enrichment.toMap(),
    }, SetOptions(merge: true));

    return true;
  }

  /// Merges pending enrichment into official branch fields and clears the pending state
  Future<void> applyBranchEnrichment(String branchId) async {
    final doc = await _branchesCollection.doc(branchId).get();
    if (!doc.exists) return;
    final branch = BranchModel.fromFirestore(doc);
    final pe = branch.pendingEnrichment;
    if (pe == null) return;

    final existingSig = branch.receiptSignature ?? BranchReceiptSignature(
      storeId: '',
      posNumberPattern: '',
      receiptPattern: '',
      headerKeywords: [],
      footerKeywords: [],
      taxNumber: '',
      commercialReg: '',
      hotline: '',
      sampleReceiptUrl: '',
      extractedSummary: '',
    );

    final updatedSig = existingSig.copyWith(
      storeId: pe.storeId.isNotEmpty ? pe.storeId : existingSig.storeId,
      posNumberPattern: pe.posNumber.isNotEmpty ? pe.posNumber : existingSig.posNumberPattern,
      taxNumber: pe.taxNumber.isNotEmpty ? pe.taxNumber : existingSig.taxNumber,
      commercialReg: pe.commercialReg.isNotEmpty ? pe.commercialReg : existingSig.commercialReg,
      hotline: pe.hotline.isNotEmpty ? pe.hotline : existingSig.hotline,
      sampleReceiptUrl: pe.sourceReceiptUrl.isNotEmpty ? pe.sourceReceiptUrl : existingSig.sampleReceiptUrl,
      scannedAt: DateTime.now(),
    );

    final updatedBranch = branch.copyWith(
      branchCode: (branch.branchCode.isEmpty || branch.branchCode == 'DEF') && pe.storeId.isNotEmpty
          ? pe.storeId
          : branch.branchCode,
      address: branch.address.isEmpty && pe.branchAddress.isNotEmpty
          ? pe.branchAddress
          : branch.address,
      receiptSignature: updatedSig,
      clearPendingEnrichment: true,
    );

    await _branchesCollection.doc(branchId).update({
      'branchCode': updatedBranch.branchCode,
      'address': updatedBranch.address,
      'receiptSignature': updatedSig.toMap(),
      'pendingEnrichment': FieldValue.delete(),
    });
  }

  /// Dismisses / deletes a pending enrichment from a branch
  Future<void> dismissBranchEnrichment(String branchId) async {
    await _branchesCollection.doc(branchId).update({
      'pendingEnrichment': FieldValue.delete(),
    });
  }

  /// Bulk merges all pending enrichments across all branches
  Future<int> applyAllPendingEnrichments() async {
    final branches = await getAllBranches();
    int count = 0;
    for (final b in branches) {
      if (b.pendingEnrichment != null && b.pendingEnrichment!.hasActionableData) {
        await applyBranchEnrichment(b.id);
        count++;
      }
    }
    return count;
  }
}
