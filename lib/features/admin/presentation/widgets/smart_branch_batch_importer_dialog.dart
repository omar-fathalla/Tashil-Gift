import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/retail_chains_service.dart';
import '../../../../core/services/smart_branch_matcher_service.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../domain/retail_chain_model.dart';

/// Result object returned to the campaign builder
class SmartBranchImportResult {
  final Set<String> chainIds;
  final Map<String, String> chainNames;
  final Map<String, Set<String>> chainSelectedBranchIds;
  final Map<String, Set<String>> chainSelectedBranchNames;
  final List<BranchModel> newlyCreatedBranches;
  final int totalBranchesCount;

  const SmartBranchImportResult({
    required this.chainIds,
    required this.chainNames,
    required this.chainSelectedBranchIds,
    required this.chainSelectedBranchNames,
    this.newlyCreatedBranches = const [],
    required this.totalBranchesCount,
  });
}

class SmartBranchBatchImporterDialog extends ConsumerStatefulWidget {
  final List<RetailChainModel> existingChains;
  final List<BranchModel> existingBranches;

  const SmartBranchBatchImporterDialog({
    super.key,
    required this.existingChains,
    required this.existingBranches,
  });

  static Future<SmartBranchImportResult?> show({
    required BuildContext context,
    required List<RetailChainModel> existingChains,
    required List<BranchModel> existingBranches,
  }) {
    return showDialog<SmartBranchImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SmartBranchBatchImporterDialog(
        existingChains: existingChains,
        existingBranches: existingBranches,
      ),
    );
  }

  @override
  ConsumerState<SmartBranchBatchImporterDialog> createState() => _SmartBranchBatchImporterDialogState();
}

class _SmartBranchBatchImporterDialogState extends ConsumerState<SmartBranchBatchImporterDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  int _activeTab = 0; // 0: Text, 1: Excel, 2: Image
  final _textController = TextEditingController();

  // Excel state
  Uint8List? _excelBytes;
  String _excelFileName = '';

  // Image state
  Uint8List? _imageBytes;
  String _imageFileName = '';
  String _imageMimeType = 'image/jpeg';

  // Analysis state
  bool _isAnalyzing = false;
  String _analyzingMessage = '';
  bool _isRegisteringNewBranches = false;
  bool _isRegisteringChain = false;
  List<RawBranchImportItem> _lastRawItems = [];

  BranchImportSummary? _summary;
  final Set<int> _selectedIndices = {};
  String _reviewFilter = 'all'; // 'all', 'matched', 'new', 'unknown'

  late List<RetailChainModel> _liveChains;
  late List<BranchModel> _liveBranches;
  final List<BranchModel> _createdBranchesAccumulator = [];

  @override
  void initState() {
    super.initState();
    _liveChains = List.from(widget.existingChains);
    _liveBranches = List.from(widget.existingBranches);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _loadSampleData() {
    _textController.text = '''1 Carrefour   El Maadi
2 Carrefour   CFC
3 Carrefour   Almaza
4 Carrefour   Alexandria
5 Carrefour   MOE
6 Hyper One   Zayed
7 Hyper One   Asher
8 Hyper One   Badr
9 El Hawary   Lebanon Square
10 Aswak   Rehab
11 Aswak   Smoha
12 Gomla   El Montzah
13 Gomla   Salah Salem (El-Obour)
14 Oscar   New Cairo
15 EL Far   South 90
16 Lulu   Twin Plaza
17 El Far   Madinaty
18 Seoudi   Dream
19 Seoudi   City Stars
20 Seoudi   Madinaty
21 Spinneys   MOA''';
  }

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        setState(() {
          _excelBytes = file.bytes;
          _excelFileName = file.name;
        });
      }
    }
  }

  Future<void> _pickImageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        final ext = (file.extension ?? '').toLowerCase();
        String mime = 'image/jpeg';
        if (ext == 'png') mime = 'image/png';
        if (ext == 'webp') mime = 'image/webp';
        if (ext == 'pdf') mime = 'application/pdf';

        setState(() {
          _imageBytes = file.bytes;
          _imageFileName = file.name;
          _imageMimeType = mime;
        });
      }
    }
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _isAnalyzing = true;
      _analyzingMessage = 'جارٍ استخراج وتدقيق البيانات...';
      _summary = null;
      _selectedIndices.clear();
    });

    try {
      List<RawBranchImportItem> rawItems = [];

      if (_activeTab == 0) {
        final text = _textController.text.trim();
        if (text.isEmpty) {
          throw const FormatException('يرجى لصق قائمة الفروع أو إدخال النص أولاً.');
        }
        rawItems = SmartBranchMatcherService.parseText(text);
      } else if (_activeTab == 1) {
        if (_excelBytes == null) {
          throw const FormatException('يرجى اختيار ملف الإكسيل أو CSV أولاً.');
        }
        if (_excelFileName.toLowerCase().endsWith('.csv')) {
          final csvStr = String.fromCharCodes(_excelBytes!);
          rawItems = SmartBranchMatcherService.parseCsv(csvStr);
        } else {
          rawItems = SmartBranchMatcherService.parseExcel(_excelBytes!, _excelFileName);
        }
      } else {
        if (_imageBytes == null) {
          throw const FormatException('يرجى اختيار صورة الجدول أو ملف PDF أولاً.');
        }
        setState(() => _analyzingMessage = 'جارٍ فحص صورة الجدول واستخراج الفروع عبر عقل Gemini 3.7 Flash...');
        rawItems = await SmartBranchMatcherService.parseImageOrPdfWithGemini(
          fileBytes: _imageBytes!,
          mimeType: _imageMimeType,
        );
      }

      if (rawItems.isEmpty) {
        throw const FormatException('لم يتم العثور على أي فروع أو سلاسل صالحة في المدخلات.');
      }

      _lastRawItems = rawItems;

      setState(() => _analyzingMessage = 'جارٍ مطابقة ${rawItems.length} فرعاً مع قاعدة بيانات النظام...');

      // Refresh live system data to ensure recent additions are present
      try {
        final service = ref.read(retailChainsServiceProvider);
        _liveChains = await service.getRetailChains();
        _liveBranches = await service.getAllBranches();
      } catch (_) {}

      final summary = SmartBranchMatcherService.matchExtractedItems(
        rawItems: rawItems,
        existingChains: _liveChains,
        existingBranches: _liveBranches,
      );

      setState(() {
        _summary = summary;
        // Select all valid items by default
        for (int i = 0; i < summary.items.length; i++) {
          final it = summary.items[i];
          if (it.status != BranchMatchStatus.unknownChain) {
            _selectedIndices.add(i);
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تنبيه: $e', style: GoogleFonts.cairo()),
            backgroundColor: colorScheme.onErrorContainer,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  /// Auto-registers missing branches in Firestore so they get real database IDs
  Future<void> _registerAllNewBranches() async {
    if (_summary == null) return;
    final newItems = _summary!.items
        .asMap()
        .entries
        .where((e) => e.value.status == BranchMatchStatus.newBranch && e.value.matchedChainId != null)
        .toList();

    if (newItems.isEmpty) return;

    setState(() {
      _isRegisteringNewBranches = true;
    });

    final service = ref.read(retailChainsServiceProvider);
    int registeredCount = 0;

    try {
      final updatedItems = List<MatchedBranchImportItem>.from(_summary!.items);

      for (final entry in newItems) {
        final index = entry.key;
        final item = entry.value;

        final arabicName = item.suggestedArabicName.isNotEmpty
            ? item.suggestedArabicName
            : item.rawItem.rawBranch;
        final city = item.suggestedCity.isNotEmpty ? item.suggestedCity : 'القاهرة';

        final cleanBranchSlug = arabicName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
        final deterministicId = '${item.matchedChainId}_$cleanBranchSlug';

        final newBranch = BranchModel(
          id: deterministicId,
          branchName: arabicName,
          retailChainId: item.matchedChainId!,
          retailChainName: item.canonicalChainName,
          city: city,
          address: '$arabicName - $city',
          branchCode: 'DEF',
          createdAt: DateTime.now(),
        );

        await service.upsertBranch(newBranch);
        _liveBranches.add(newBranch);
        _createdBranchesAccumulator.add(newBranch);
        registeredCount++;

        // Update item in summary
        updatedItems[index] = item.copyWith(
          status: BranchMatchStatus.exactMatch,
          matchedBranchId: newBranch.id,
          matchedBranchName: newBranch.branchName,
          branchModel: newBranch,
          confidence: 1.0,
        );
      }

      setState(() {
        _summary = BranchImportSummary(items: updatedItems);
        // Select all newly registered items
        for (final entry in newItems) {
          _selectedIndices.add(entry.key);
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل وتوثيق $registeredCount فرعاً جديداً في النظام بنجاح! ✓',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء التسجيل: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegisteringNewBranches = false);
      }
    }
  }

  /// Copies a professionally formatted WhatsApp / Email message requesting sample POS cashier receipts
  void _copyPosReceiptRequestMessage() {
    if (_summary == null) return;
    final message = SmartBranchMatcherService.generatePosReceiptRequestMessage(_summary!);
    Clipboard.setData(ClipboardData(text: message));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم نسخ رسالة طلب بونات الكاشير إلى الحافظة بنجاح! جاهزة للإرسال للعميل عبر واتساب أو الإيميل. 📋',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: colorScheme.onTertiaryFixedVariant,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Registers a single newly discovered branch in Firestore
  Future<void> _registerSingleBranch(MatchedBranchImportItem item, int index) async {
    if (item.matchedChainId == null || item.matchedChainId!.isEmpty) return;
    final service = ref.read(retailChainsServiceProvider);

    try {
      final arabicName = item.suggestedArabicName.isNotEmpty
          ? item.suggestedArabicName
          : item.rawItem.rawBranch;
      final city = item.suggestedCity.isNotEmpty ? item.suggestedCity : 'القاهرة';

      final cleanBranchSlug = arabicName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
      final deterministicId = '${item.matchedChainId}_$cleanBranchSlug';

      final newBranch = BranchModel(
        id: deterministicId,
        branchName: arabicName,
        retailChainId: item.matchedChainId!,
        retailChainName: item.canonicalChainName,
        city: city,
        address: '$arabicName - $city',
        branchCode: 'DEF',
        createdAt: DateTime.now(),
      );

      await service.upsertBranch(newBranch);
      _liveBranches.add(newBranch);
      _createdBranchesAccumulator.add(newBranch);

      if (_summary != null) {
        final updatedItems = List<MatchedBranchImportItem>.from(_summary!.items);
        updatedItems[index] = item.copyWith(
          status: BranchMatchStatus.exactMatch,
          matchedBranchId: newBranch.id,
          matchedBranchName: newBranch.branchName,
          branchModel: newBranch,
          confidence: 1.0,
        );

        setState(() {
          _summary = BranchImportSummary(items: updatedItems);
          _selectedIndices.add(index);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم توثيق وتسجيل فرع "$arabicName" في النظام بنجاح! ✓',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تسجيل الفرع: $e'), backgroundColor: colorScheme.error),
        );
      }
    }
  }

  /// Registers an unknown chain directly in Firestore and immediately re-evaluates all import items
  Future<void> _registerSingleChain(String canonicalChainName, String rawChain) async {
    final chainName = canonicalChainName.isNotEmpty ? canonicalChainName : rawChain;
    final cleanSlug = chainName.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');

    setState(() => _isRegisteringChain = true);
    final service = ref.read(retailChainsServiceProvider);

    try {
      final newChain = RetailChainModel(
        id: cleanSlug.isNotEmpty ? cleanSlug : 'chain_${DateTime.now().millisecondsSinceEpoch}',
        name: chainName,
        slug: cleanSlug,
        branchesCount: 0,
        createdAt: DateTime.now(),
      );

      await service.addRetailChain(newChain);

      // Update local live chains
      _liveChains.removeWhere((c) => c.id == newChain.id || c.name == newChain.name);
      _liveChains.add(newChain);

      // Re-run matching on raw items
      final rawItemsToMatch = _lastRawItems.isNotEmpty
          ? _lastRawItems
          : (_summary?.items.map((i) => i.rawItem).toList() ?? []);

      final summary = SmartBranchMatcherService.matchExtractedItems(
        rawItems: rawItemsToMatch,
        existingChains: _liveChains,
        existingBranches: _liveBranches,
      );

      setState(() {
        _summary = summary;
        // Auto-select valid items
        for (int i = 0; i < summary.items.length; i++) {
          if (summary.items[i].status != BranchMatchStatus.unknownChain) {
            _selectedIndices.add(i);
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل سلسلة "$chainName" في النظام بنجاح! ✓ تحولت فروعها تلقائياً إلى فروع جديدة مهيأة للتسجيل.',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تسجيل السلسلة: $e'), backgroundColor: colorScheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegisteringChain = false);
      }
    }
  }

  /// Registers all discovered unknown chains in one click
  Future<void> _registerAllUnknownChains() async {
    if (_summary == null) return;
    final unknownItems = _summary!.items.where((i) => i.status == BranchMatchStatus.unknownChain).toList();
    if (unknownItems.isEmpty) return;

    final uniqueChains = <String, String>{};
    for (final it in unknownItems) {
      final name = it.canonicalChainName.isNotEmpty ? it.canonicalChainName : it.rawItem.rawChain;
      uniqueChains[name] = it.rawItem.rawChain;
    }

    setState(() => _isRegisteringChain = true);
    final service = ref.read(retailChainsServiceProvider);
    int registeredCount = 0;

    try {
      for (final entry in uniqueChains.entries) {
        final chainName = entry.key;
        final cleanSlug = chainName.toLowerCase().trim().toEnglishDigits().replaceAll(RegExp(r'\s+'), '-');

        final newChain = RetailChainModel(
          id: cleanSlug.isNotEmpty ? cleanSlug : 'chain_${DateTime.now().millisecondsSinceEpoch}',
          name: chainName,
          slug: cleanSlug,
          branchesCount: 0,
          createdAt: DateTime.now(),
        );

        await service.addRetailChain(newChain);
        _liveChains.removeWhere((c) => c.id == newChain.id || c.name == newChain.name);
        _liveChains.add(newChain);
        registeredCount++;
      }

      final rawItemsToMatch = _lastRawItems.isNotEmpty
          ? _lastRawItems
          : (_summary?.items.map((i) => i.rawItem).toList() ?? []);

      final summary = SmartBranchMatcherService.matchExtractedItems(
        rawItems: rawItemsToMatch,
        existingChains: _liveChains,
        existingBranches: _liveBranches,
      );

      setState(() {
        _summary = summary;
        // Auto-select valid items
        for (int i = 0; i < summary.items.length; i++) {
          if (summary.items[i].status != BranchMatchStatus.unknownChain) {
            _selectedIndices.add(i);
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل $registeredCount سلاسل جديدة في النظام بنجاح! ✓ أصبحت كافة الفروع جاهزة للتسجيل الآن.',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تسجيل السلاسل: $e'), backgroundColor: colorScheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegisteringChain = false);
      }
    }
  }

  void _applySelectionToCampaign() {
    if (_summary == null || _selectedIndices.isEmpty) return;

    final Set<String> chainIds = {};
    final Map<String, String> chainNames = {};
    final Map<String, Set<String>> chainSelectedBranchIds = {};
    final Map<String, Set<String>> chainSelectedBranchNames = {};

    int totalAppliedBranches = 0;

    for (final idx in _selectedIndices) {
      if (idx < 0 || idx >= _summary!.items.length) continue;
      final item = _summary!.items[idx];

      if (item.matchedChainId != null && item.matchedChainId!.isNotEmpty) {
        final cId = item.matchedChainId!;
        chainIds.add(cId);
        chainNames[cId] = item.canonicalChainName;

        chainSelectedBranchIds.putIfAbsent(cId, () => <String>{});
        chainSelectedBranchNames.putIfAbsent(cId, () => <String>{});

        if (item.matchedBranchId != null && item.matchedBranchId!.isNotEmpty) {
          chainSelectedBranchIds[cId]!.add(item.matchedBranchId!);
        }
        if (item.matchedBranchName != null && item.matchedBranchName!.isNotEmpty) {
          chainSelectedBranchNames[cId]!.add(item.matchedBranchName!);
        } else if (item.rawItem.rawBranch.isNotEmpty) {
          chainSelectedBranchNames[cId]!.add(item.rawItem.rawBranch);
        }

        totalAppliedBranches++;
      }
    }

    final result = SmartBranchImportResult(
      chainIds: chainIds,
      chainNames: chainNames,
      chainSelectedBranchIds: chainSelectedBranchIds,
      chainSelectedBranchNames: chainSelectedBranchNames,
      newlyCreatedBranches: _createdBranchesAccumulator,
      totalBranchesCount: totalAppliedBranches,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 740),
        child: Column(
          children: [
            // 1. Header
            _buildDialogHeader(colorScheme),
            const Divider(height: 1),

            // 2. Body
            Expanded(
              child: _summary == null
                  ? _buildInputForm(colorScheme)
                  : _buildReviewResultsView(colorScheme),
            ),

            // 3. Actions Footer
            const Divider(height: 1),
            _buildDialogFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: colorScheme.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'استيراد وتحديد الفروع بالذكاء الاصطناعي (Smart Branch Importer)',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'ألصق قائمة نصية، ارفع ملف إكسيل أو صورة لفحص ومطابقة كافة الفروع بضغطة زر واحدة',
                  style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }

  Widget _buildInputForm(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Input Tabs
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.content_paste_rounded, size: 18),
                label: Text('لصق نص / جدول'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.table_chart_rounded, size: 18),
                label: Text('ملف إكسيل / CSV'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.document_scanner_rounded, size: 18),
                label: Text('صورة / PDF (Gemini 3.7)'),
              ),
            ],
            selected: {_activeTab},
            onSelectionChanged: (set) => setState(() => _activeTab = set.first),
          ),
          const SizedBox(height: 18),

          // Tab 0: Text Paste
          if (_activeTab == 0) ...[
            Row(
              children: [
                Text(
                  'انسخ الجدول من إيميل، واتساب أو إكسيل والصقه هنا مباشرة:',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadSampleData,
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                  label: Text('تجربة نموذج الـ 21 فرعاً', style: GoogleFonts.cairo(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              maxLines: 10,
              style: GoogleFonts.cairo(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: '''مثال:
1 Carrefour   El Maadi
2 Carrefour   CFC
6 Hyper One   Zayed
12 Gomla   El Montzah
21 Spinneys   MOA''',
                hintStyle: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]

          // Tab 1: Excel / CSV File
          else if (_activeTab == 1) ...[
            Text(
              'اختر ملف إكسيل (.xlsx) أو ملف CSV يحتوي على أعمدة السلاسل والفروع:',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickExcelFile,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(
                      _excelBytes != null ? Icons.task_alt_rounded : Icons.cloud_upload_rounded,
                      size: 48,
                      color: _excelBytes != null ? colorScheme.tertiary : colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _excelBytes != null ? _excelFileName : 'اضغط لاختيار ملف الإكسيل أو CSV',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _excelBytes != null
                          ? '${(_excelBytes!.length / 1024).toStringAsFixed(1)} كيلوبايت • جاهز للفحص'
                          : 'يدعم صيغ .xlsx و .csv مع كشف تلقائي للأعمدة',
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ]

          // Tab 2: Image / PDF Screenshot (Gemini 3.7 Flash)
          else ...[
            Row(
              children: [
                Text(
                  'اختر صورة لقطة شاشة للجدول أو ملف PDF مصور:',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.tertiaryFixedDim),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: colorScheme.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        'Gemini 3.7 Flash Vision',
                        style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickImageFile,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      _imageBytes != null ? Icons.image_rounded : Icons.add_photo_alternate_rounded,
                      size: 48,
                      color: _imageBytes != null ? colorScheme.primary : colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _imageBytes != null ? _imageFileName : 'اضغط لرفع لقطة الشاشة أو صورة الجدول',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _imageBytes != null
                          ? '${(_imageBytes!.length / 1024).toStringAsFixed(1)} كيلوبايت • جاهز للتحليل الذكي'
                          : 'يدعم صيغ JPG, PNG, WEBP, PDF مع التعرف الضوئي التلقائي',
                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Analysis In Progress Card
          if (_isAnalyzing) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _analyzingMessage,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewResultsView(ColorScheme colorScheme) {
    final summary = _summary!;
    final filteredItems = summary.items.asMap().entries.where((entry) {
      if (_reviewFilter == 'matched') {
        return entry.value.status == BranchMatchStatus.exactMatch || entry.value.status == BranchMatchStatus.fuzzyMatch;
      }
      if (_reviewFilter == 'new') {
        return entry.value.status == BranchMatchStatus.newBranch;
      }
      if (_reviewFilter == 'unknown') {
        return entry.value.status == BranchMatchStatus.unknownChain;
      }
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. KPI Row
          Row(
            children: [
              _buildKpiBadge('إجمالي الفروع', '${summary.totalCount}', colorScheme.primary),
              const SizedBox(width: 8),
              _buildKpiBadge('متطابق بالسيستم ✓', '${summary.matchedCount}', colorScheme.tertiary),
              const SizedBox(width: 8),
              _buildKpiBadge('فروع جديدة ⚠️', '${summary.newBranchesCount}', colorScheme.onSecondaryFixedVariant),
              const SizedBox(width: 8),
              if (summary.unknownChainsCount > 0)
                _buildKpiBadge('سلاسل غير مسجلة ❌', '${summary.unknownChainsCount}', colorScheme.onErrorContainer)
              else
                _buildKpiBadge('سلاسل مكتشفة 🏢', '${summary.matchedChainNames.length}', colorScheme.primary),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Actions & Filter Toolbar (Responsive Wrap + Dropdown Menu)
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Filter Dropdown Menu
                _buildFilterDropdown(colorScheme, summary),

                // Action Buttons (Wrapped to guarantee zero overflow)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Copy WhatsApp / Email Request Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onTertiaryFixedVariant,
                        side: BorderSide(color: colorScheme.tertiaryFixedDim),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _copyPosReceiptRequestMessage,
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: Text(
                        '📋 طلب بونات الكاشير (WhatsApp)',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Auto-register unknown chains button
                    if (summary.unknownChainsCount > 0)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isRegisteringChain ? null : _registerAllUnknownChains,
                        icon: _isRegisteringChain
                            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.domain_add_rounded, size: 15),
                        label: Text(
                          '+ تسجيل السلاسل (${summary.unknownChainsCount})',
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),

                    // Auto-register missing branches button
                    if (summary.newBranchesCount > 0)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.secondaryContainer,
                          foregroundColor: colorScheme.onSecondaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isRegisteringNewBranches ? null : _registerAllNewBranches,
                        icon: _isRegisteringNewBranches
                            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_business_rounded, size: 15),
                        label: Text(
                          '+ تسجيل الفروع (${summary.newBranchesCount})',
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Selection Summary Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _selectedIndices.length == summary.items.length,
                  tristate: _selectedIndices.isNotEmpty && _selectedIndices.length < summary.items.length,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedIndices.addAll(List.generate(summary.items.length, (i) => i));
                      } else {
                        _selectedIndices.clear();
                      }
                    });
                  },
                ),
                Text(
                  'تم تحديد ${_selectedIndices.length} من ${summary.items.length} فرع للتطبيق في الحملة',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _summary = null),
                  child: Text('تعديل المدخلات', style: GoogleFonts.cairo(fontSize: 11.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // 4. Results List
          Expanded(
            child: ListView.separated(
              itemCount: filteredItems.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final entry = filteredItems[idx];
                final itemIndex = entry.key;
                final item = entry.value;
                final isSelected = _selectedIndices.contains(itemIndex);

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIndices.remove(itemIndex);
                      } else {
                        _selectedIndices.add(itemIndex);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedIndices.add(itemIndex);
                              } else {
                                _selectedIndices.remove(itemIndex);
                              }
                            });
                          },
                        ),
                        Container(
                          width: 28,
                          alignment: Alignment.center,
                          child: Text(
                            '${item.rawItem.rowNumber}',
                            style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.outline),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Detected chain badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colorScheme.primaryFixedDim),
                          ),
                          child: Text(
                            item.canonicalChainName.isNotEmpty ? item.canonicalChainName : item.rawItem.rawChain,
                            style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Branch Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item.rawItem.rawBranch,
                                    style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                  if (item.matchedBranchName != null && item.matchedBranchName != item.rawItem.rawBranch) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.arrow_forward_rounded, size: 12, color: colorScheme.outline),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.matchedBranchName!,
                                      style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onTertiaryFixedVariant, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                'المدينة: ${item.suggestedCity} • النص الأصلي: ${item.rawItem.rawChain} - ${item.rawItem.rawBranch}',
                                style: GoogleFonts.cairo(fontSize: 10.5, color: colorScheme.outline),
                              ),
                            ],
                          ),
                        ),

                        // Status Badge & Inline Quick Actions
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusBadge(item.status),
                            if (item.status == BranchMatchStatus.unknownChain) ...[
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _isRegisteringChain
                                    ? null
                                    : () => _registerSingleChain(item.canonicalChainName, item.rawItem.rawChain),
                                icon: const Icon(Icons.add_circle_outline_rounded, size: 13),
                                label: Text(
                                  '+ تسجيل السلسلة ("${item.canonicalChainName.isNotEmpty ? item.canonicalChainName : item.rawItem.rawChain}")',
                                  style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ] else if (item.status == BranchMatchStatus.newBranch) ...[
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.onTertiaryFixedVariant,
                                  side: BorderSide(color: colorScheme.tertiaryFixedDim),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _registerSingleBranch(item, itemIndex),
                                icon: const Icon(Icons.add_business_rounded, size: 13),
                                label: Text(
                                  '+ حفظ هذا الفرع',
                                  style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(ColorScheme colorScheme, BranchImportSummary summary) {
    final validFilters = ['all', 'matched', 'new', if (summary.unknownChainsCount > 0) 'unknown'];
    final currentFilter = validFilters.contains(_reviewFilter) ? _reviewFilter : 'all';

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentFilter,
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Theme.of(context).cardColor,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_rounded, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('عرض: كل الفروع (${summary.totalCount})'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'matched',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Text('المتطابقة بالسيستم (${summary.matchedCount})'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'new',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text('فروع جديدة (${summary.newBranchesCount})'),
                ],
              ),
            ),
            if (summary.unknownChainsCount > 0)
              DropdownMenuItem(
                value: 'unknown',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Text(
                      'سلاسل غير مسجلة (${summary.unknownChainsCount})',
                      style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _reviewFilter = val);
          },
        ),
      ),
    );
  }

  Widget _buildKpiBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: GoogleFonts.cairo(fontSize: 10.5, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BranchMatchStatus status) {
    switch (status) {
      case BranchMatchStatus.exactMatch:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.tertiaryFixedDim),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: colorScheme.tertiary),
              const SizedBox(width: 4),
              Text('متطابق بدقة ✓', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer)),
            ],
          ),
        );
      case BranchMatchStatus.fuzzyMatch:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.primaryFixedDim),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 13, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text('مطابقة ذكية', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
            ],
          ),
        );
      case BranchMatchStatus.newBranch:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.primaryFixedDim),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 4),
              Text('فرع جديد', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer)),
            ],
          ),
        );
      case BranchMatchStatus.unknownChain:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.errorContainer),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: colorScheme.error),
              const SizedBox(width: 4),
              Text('سلسلة غير معروفة', style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onErrorContainer)),
            ],
          ),
        );
    }
  }

  Widget _buildDialogFooter(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          const Spacer(),

          if (_summary == null) ...[
            FilledButton.icon(
              onPressed: _isAnalyzing ? null : _runAnalysis,
              icon: _isAnalyzing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(
                _isAnalyzing ? 'جارٍ الفحص...' : '⚡ فحص ومطابقة الفروع',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _selectedIndices.isEmpty ? null : _applySelectionToCampaign,
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                '🚀 اعتماد وتحديد الـ (${_selectedIndices.length}) فرع في الحملة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
