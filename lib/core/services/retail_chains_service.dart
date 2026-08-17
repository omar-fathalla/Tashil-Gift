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

  // --- RETAIL CHAINS STREAMS & QUERIES ---

  Stream<List<RetailChainModel>> getRetailChainsStream() {
    return _chainsCollection
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => RetailChainModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          return list;
        });
  }

  Future<List<RetailChainModel>> getRetailChains() async {
    final snapshot = await _chainsCollection.get();
    final list = snapshot.docs
        .map((doc) => RetailChainModel.fromFirestore(doc))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> addRetailChain(RetailChainModel chain) async {
    final cleanSlug = chain.slug.toLowerCase().trim().toEnglishDigits();
    final docRef = chain.id.isNotEmpty ? _chainsCollection.doc(chain.id) : _chainsCollection.doc();
    
    final toSave = chain.copyWith(
      id: docRef.id,
      slug: cleanSlug,
      createdAt: chain.createdAt ?? DateTime.now(),
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
          final list = snapshot.docs
              .map((doc) => BranchModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => a.branchName.compareTo(b.branchName));
          return list;
        });
  }

  Future<List<BranchModel>> getBranchesForChain(String retailChainId) async {
    if (retailChainId.trim().isEmpty) return [];
    final snapshot = await _branchesCollection
        .where('retailChainId', isEqualTo: retailChainId)
        .get();
    final list = snapshot.docs
        .map((doc) => BranchModel.fromFirestore(doc))
        .toList();
    list.sort((a, b) => a.branchName.compareTo(b.branchName));
    return list;
  }

  Stream<List<BranchModel>> getAllBranchesStream() {
    return _branchesCollection
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => BranchModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => a.branchName.compareTo(b.branchName));
          return list;
        });
  }

  Future<void> addBranch(BranchModel branch) async {
    final docRef = branch.id.isNotEmpty ? _branchesCollection.doc(branch.id) : _branchesCollection.doc();
    final cleanCode = branch.branchCode.trim().toEnglishDigits();

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
  }

  Future<void> updateBranch(BranchModel branch) async {
    final cleanCode = branch.branchCode.trim().toEnglishDigits();
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
      final count = snap.docs.length;
      await _chainsCollection.doc(retailChainId).set({
        'branchesCount': count,
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {}
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
