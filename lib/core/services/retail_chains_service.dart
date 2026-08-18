import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_service.dart';
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

  Future<void> addRetailChain(RetailChainModel chain) async {
    final cleanSlug = chain.slug.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');
    final deterministicId = cleanSlug.isNotEmpty ? cleanSlug : chain.name.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');
    
    // Check if chain already exists by slug or name
    final existingChains = await getRetailChains();
    final existing = existingChains.where((c) =>
        c.id == deterministicId ||
        c.slug.toLowerCase() == cleanSlug ||
        c.name.trim().toLowerCase() == chain.name.trim().toLowerCase()
    ).firstOrNull;

    final docId = existing?.id ?? (deterministicId.isNotEmpty ? deterministicId : _chainsCollection.doc().id);
    final docRef = _chainsCollection.doc(docId);
    
    final toSave = chain.copyWith(
      id: docId,
      slug: cleanSlug.isNotEmpty ? cleanSlug : docId,
      createdAt: existing?.createdAt ?? chain.createdAt ?? DateTime.now(),
    );

    await docRef.set(toSave.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
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
    final snapshot = await _branchesCollection
        .where('retailChainId', isEqualTo: retailChainId)
        .get();
    final rawList = snapshot.docs
        .map((doc) => BranchModel.fromFirestore(doc))
        .toList();
    return _deduplicateBranchList(rawList);
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
  /// it merges and updates the existing document instead of creating a duplicate.
  Future<bool> addBranch(BranchModel branch) async {
    final chainId = branch.retailChainId.trim().toLowerCase();
    final cleanCode = branch.branchCode.trim().toUpperCase().toEnglishDigits();
    final cleanName = branch.branchName.trim().toLowerCase();
    final storeId = branch.receiptSignature?.storeId.trim().toEnglishDigits() ?? '';

    // Check for existing branch in the same chain
    final existingBranchesSnap = await _branchesCollection
        .where('retailChainId', isEqualTo: branch.retailChainId)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? duplicateDoc;

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
        duplicateDoc = doc;
        break;
      }
    }

    // Deterministic ID if creating new doc
    final deterministicDocId = branch.id.isNotEmpty
        ? branch.id
        : (duplicateDoc?.id ??
            '${chainId}_${cleanCode.isNotEmpty ? cleanCode.toLowerCase() : cleanName.replaceAll(RegExp(r'\s+'), '_')}');

    final docRef = _branchesCollection.doc(deterministicDocId);
    final isDuplicate = duplicateDoc != null;

    final toSave = branch.copyWith(
      id: docRef.id,
      branchCode: cleanCode,
      createdAt: isDuplicate ? (BranchModel.fromFirestore(duplicateDoc).createdAt ?? DateTime.now()) : (branch.createdAt ?? DateTime.now()),
    );

    await docRef.set(toSave.toFirestore(), SetOptions(merge: true)).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    // Update branches count in parent chain
    await _recalculateChainBranchesCount(branch.retailChainId);

    return isDuplicate;
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
}
