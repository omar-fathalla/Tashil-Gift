import 'package:flutter_test/flutter_test.dart';
import 'package:al_mraay/core/services/smart_branch_matcher_service.dart';
import 'package:al_mraay/features/admin/domain/retail_chain_model.dart';

void main() {
  group('SmartBranchMatcherService Tests', () {
    test('Parses inline numbered string correctly into 21 items', () {
      const input = '''#اسم المؤسسة (Account)الفرع (Branch)1Carrefour   El Maadi   2Carrefour   CFC   3Carrefour   Almaza   4Carrefour   Alexandria   5Carrefour   MOE   6Hyper One   Zayed   7Hyper One   Asher   8Hyper One   Badr   9El Hawary   Lebanon Square   10Aswak   Rehab   11Aswak   Smoha   12Gomla   El Montzah   13Gomla   Salah Salem (El-Obour)   14Oscar   New Cairo   15EL Far   South 90   16Lulu   Twin Plaza   17El Far   Madinaty   18Seoudi   Dream   19Seoudi   City Stars   20Seoudi   Madinaty   21Spinneys   MOA''';

      final items = SmartBranchMatcherService.parseText(input);

      expect(items.length, 21);
      expect(items[0].rawChain, 'Carrefour');
      expect(items[0].rawBranch, 'El Maadi');

      expect(items[1].rawChain, 'Carrefour');
      expect(items[1].rawBranch, 'CFC');

      expect(items[5].rawChain, 'Hyper One');
      expect(items[5].rawBranch, 'Zayed');

      expect(items[8].rawChain, 'El Hawary');
      expect(items[8].rawBranch, 'Lebanon Square');

      expect(items[9].rawChain, 'Aswak');
      expect(items[9].rawBranch, 'Rehab');

      expect(items[11].rawChain, 'Gomla');
      expect(items[11].rawBranch, 'El Montzah');

      expect(items[13].rawChain, 'Oscar');
      expect(items[13].rawBranch, 'New Cairo');

      expect(items[14].rawChain, 'EL Far');
      expect(items[14].rawBranch, 'South 90');

      expect(items[15].rawChain, 'Lulu');
      expect(items[15].rawBranch, 'Twin Plaza');

      expect(items[17].rawChain, 'Seoudi');
      expect(items[17].rawBranch, 'Dream');

      expect(items[20].rawChain, 'Spinneys');
      expect(items[20].rawBranch, 'MOA');
    });

    test('Parses multiline tabular input correctly into 21 items', () {
      const input = '''
Carrefour	El Maadi
Carrefour	CFC
Carrefour	Almaza
Carrefour	Alexandria
Carrefour	MOE
Hyper One	Zayed
Hyper One	Asher
Hyper One	Badr
El Hawary	Lebanon Square
Aswak	Rehab
Aswak	Smoha
Gomla	El Montzah
Gomla	Salah Salem (El-Obour)
Oscar	New Cairo
EL Far	South 90
Lulu	Twin Plaza
El Far	Madinaty
Seoudi	Dream
Seoudi	City Stars
Seoudi	Madinaty
Spinneys	MOA
''';

      final items = SmartBranchMatcherService.parseText(input);
      expect(items.length, 21);
      expect(items[0].rawChain, 'Carrefour');
      expect(items[0].rawBranch, 'El Maadi');
      expect(items[20].rawChain, 'Spinneys');
      expect(items[20].rawBranch, 'MOA');
    });

    test('Matches chains and branches with existing database', () {
      final existingChains = [
        RetailChainModel(id: 'carrefour', name: 'كارفور', slug: 'carrefour'),
        RetailChainModel(id: 'hyper-one', name: 'هايبر وان', slug: 'hyper-one'),
        RetailChainModel(id: 'gomla-market', name: 'جملة ماركت', slug: 'gomla-market'),
        RetailChainModel(id: 'spinneys', name: 'سبينس', slug: 'spinneys'),
      ];

      final existingBranches = [
        BranchModel(
          id: 'b_carrefour_maadi',
          branchName: 'المعادي (القاهرة)',
          retailChainId: 'carrefour',
          retailChainName: 'كارفور',
          city: 'القاهرة',
        ),
        BranchModel(
          id: 'b_carrefour_cfc',
          branchName: 'كايرو فيستيفال سيتي',
          retailChainId: 'carrefour',
          retailChainName: 'كارفور',
          city: 'القاهرة',
        ),
        BranchModel(
          id: 'b_spinneys_moa',
          branchName: 'مول العرب (الجيزة)',
          retailChainId: 'spinneys',
          retailChainName: 'سبينس',
          city: 'الجيزة',
        ),
      ];

      final rawItems = [
        const RawBranchImportItem(rowNumber: 1, rawChain: 'Carrefour', rawBranch: 'El Maadi'),
        const RawBranchImportItem(rowNumber: 2, rawChain: 'Carrefour', rawBranch: 'CFC'),
        const RawBranchImportItem(rowNumber: 3, rawChain: 'Carrefour', rawBranch: 'New Branch'),
        const RawBranchImportItem(rowNumber: 4, rawChain: 'Spinneys', rawBranch: 'MOA'),
      ];

      final summary = SmartBranchMatcherService.matchExtractedItems(
        rawItems: rawItems,
        existingChains: existingChains,
        existingBranches: existingBranches,
      );

      expect(summary.totalCount, 4);
      expect(summary.matchedCount, 3);
      expect(summary.newBranchesCount, 1);

      expect(summary.items[0].status, BranchMatchStatus.exactMatch);
      expect(summary.items[0].matchedBranchId, 'b_carrefour_maadi');

      expect(summary.items[1].status, BranchMatchStatus.exactMatch);
      expect(summary.items[1].matchedBranchId, 'b_carrefour_cfc');

      expect(summary.items[2].status, BranchMatchStatus.newBranch);

      expect(summary.items[3].status, BranchMatchStatus.exactMatch);
      expect(summary.items[3].matchedBranchId, 'b_spinneys_moa');
    });

    test('Generates structured WhatsApp / Email receipt request message correctly', () {
      final existingChains = [
        RetailChainModel(id: 'carrefour', name: 'كارفور', slug: 'carrefour'),
      ];

      final existingBranches = [
        BranchModel(
          id: 'b_carrefour_maadi',
          branchName: 'المعادي',
          retailChainId: 'carrefour',
          retailChainName: 'كارفور',
        ),
      ];

      final rawItems = [
        const RawBranchImportItem(rowNumber: 1, rawChain: 'Carrefour', rawBranch: 'El Maadi'),
        const RawBranchImportItem(rowNumber: 2, rawChain: 'Carrefour', rawBranch: 'Almaza'),
        const RawBranchImportItem(rowNumber: 3, rawChain: 'EL Far', rawBranch: 'South 90'),
      ];

      final summary = SmartBranchMatcherService.matchExtractedItems(
        rawItems: rawItems,
        existingChains: existingChains,
        existingBranches: existingBranches,
      );

      final message = SmartBranchMatcherService.generatePosReceiptRequestMessage(
        summary,
        campaignTitle: 'حملة الصيف الكبرى 2026',
      );

      expect(message.contains('حملة الصيف الكبرى 2026'), isTrue);
      expect(message.contains('سلاسل ومنافذ جديدة مطلوب بونات كاشير لها:'), isTrue);
      expect(message.contains('الفار'), isTrue);
      expect(message.contains('فروع جديدة تحتاج بونات للتوثيق والربط البصمي:'), isTrue);
      expect(message.contains('سيتي سنتر ألماظة'), isTrue);
      expect(message.contains('متطلبات صورة البونة المطلوبة:'), isTrue);
      expect(message.contains('Store ID & Tax ID'), isTrue);
    });
  });
}
