import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';

class CompanyGiftsScreen extends ConsumerStatefulWidget {
  const CompanyGiftsScreen({super.key});

  @override
  ConsumerState<CompanyGiftsScreen> createState() => _CompanyGiftsScreenState();
}

class _CompanyGiftsScreenState extends ConsumerState<CompanyGiftsScreen> {
  String? _selectedCompanySlug;
  String? _selectedCompanyName;
  final TextEditingController _companySearchController = TextEditingController();
  final TextEditingController _giftNameController = TextEditingController();
  final TextEditingController _giftQuantityController = TextEditingController();
  final FocusNode _giftNameFocusNode = FocusNode();
  final FocusNode _giftQuantityFocusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _companySearchController.dispose();
    _giftNameController.dispose();
    _giftQuantityController.dispose();
    _giftNameFocusNode.dispose();
    _giftQuantityFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Widget? actionBadge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?actionBadge,
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _addGift() async {
    if (_isLoading) return;

    if (_selectedCompanySlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى اختيار الشركة أولاً',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final name = _giftNameController.text.trim();
    final qtyText = _giftQuantityController.text.trim();
    
    if (name.isEmpty || qtyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى إدخال اسم الهدية والكمية',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final quantity = qtyText.toIntOrNull();
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الكمية يجب أن تكون رقماً صحيحاً أكبر من الصفر',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final docRef = ref.read(firestoreProvider).collection('company_gifts').doc();
      final slug = _selectedCompanySlug!.toLowerCase().trim();
      final companyName = _selectedCompanyName ?? _selectedCompanySlug!;

      await docRef.set({
        'id': docRef.id,
        'companySlug': slug,
        'companyName': companyName,
        'name': name,
        'giftName': name,
        'totalQuantity': quantity,
        'availableQuantity': quantity,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          // Firestore cache applies the mutation immediately and syncs to server in background
        },
      );

      // Clear fields and return focus to gift name so user can add another gift immediately
      _giftNameController.clear();
      _giftQuantityController.clear();

      if (mounted) {
        _giftNameFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تمت إضافة الهدية "$name" بنجاح',
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppErrorHandler.getFriendlyMessage(e, defaultMessage: 'حدث خطأ أثناء إضافة الهدية'),
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showEditGiftDialog(Map<String, dynamic> gift) {
    final TextEditingController editQtyController = TextEditingController(text: gift['availableQuantity'].toString());
    final colorScheme = Theme.of(context).colorScheme;
    final giftTitle = gift['giftName'] ?? gift['name'] ?? 'الهدية';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(
            'تعديل الكمية المتاحة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الهدية: $giftTitle',
                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: editQtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                autofocus: true,
                style: GoogleFonts.cairo(),
                decoration: InputDecoration(
                  labelText: 'الكمية المتاحة',
                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final qty = editQtyController.text.trim().toIntOrNull();
                if (qty != null && qty >= 0) {
                  try {
                    await ref.read(firestoreProvider).collection('company_gifts').doc(gift['id']).update({
                      'availableQuantity': qty,
                    }).timeout(const Duration(milliseconds: 500), onTimeout: () {});
                  } catch (_) {}
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );
  }

  void _deleteGift(String giftId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text('تأكيد الحذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          content: Text('هل أنت متأكد من رغبتك في حذف هذه الهدية؟', style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await ref.read(firestoreProvider).collection('company_gifts').doc(giftId).delete().timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firestore = ref.watch(firestoreProvider);
    final isAr = ref.isArabic;
    final strings = AppStrings.of(ref);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.card_giftcard, color: colorScheme.onPrimaryContainer, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.giftsTitle,
                            style: GoogleFonts.cairo(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            strings.giftsSubtitle,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Section 1: Company Selector with Search & Dropdown
                _buildSectionCard(
                  context: context,
                  icon: Icons.business,
                  title: isAr ? 'تحديد الشركة' : 'Select Company',
                  subtitle: isAr ? 'اختر الشركة بالبحث عن طريق الاسم أو كود الشركة (Slug) أو من القائمة' : 'Select company by searching name, slug code, or from dropdown',
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: firestore.collection('companies').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        if (snapshot.hasError) {
                          return Text('خطأ: ${snapshot.error}', style: GoogleFonts.cairo(color: colorScheme.error));
                        }
                        
                        final docs = snapshot.data?.docs ?? [];
                        final companies = docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {
                            'id': doc.id,
                            'slug': (data['slug'] ?? doc.id).toString().trim(),
                            'name': (data['name'] ?? 'بدون اسم').toString().trim(),
                          };
                        }).toList();

                        if (companies.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Text(
                                  'لا توجد شركات مكوّدة حالياً، يرجى تكويد شركة أولاً',
                                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }

                        // Filter companies based on search query (by name or by slug code)
                        final searchQuery = _companySearchController.text.trim().toLowerCase();
                        final filteredCompanies = companies.where((c) {
                          if (searchQuery.isEmpty) return true;
                          final name = c['name']!.toLowerCase();
                          final slug = c['slug']!.toLowerCase();
                          return name.contains(searchQuery) || slug.contains(searchQuery);
                        }).toList();

                        // Selected Company Details
                        final selectedCompany = companies.where((c) => c['slug'] == _selectedCompanySlug).firstOrNull;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Search Bar for Typing Search by Name or Code
                            TextField(
                              controller: _companySearchController,
                              style: GoogleFonts.cairo(),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'ابحث باسم الشركة أو كود الشركة (مثال: جهينة أو juhayna)...',
                                hintStyle: GoogleFonts.cairo(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                                prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        tooltip: 'مسح البحث',
                                        onPressed: () {
                                          _companySearchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. Dropdown Selector (with instant search results integration)
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey('gifts_dropdown_${_selectedCompanySlug}_${filteredCompanies.length}'),
                                    initialValue: filteredCompanies.any((c) => c['slug'] == _selectedCompanySlug)
                                        ? _selectedCompanySlug
                                        : null,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'أو اختر من القائمة المنسدلة',
                                      labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    dropdownColor: colorScheme.surfaceContainerHigh,
                                    icon: Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
                                    hint: Text(
                                      filteredCompanies.isEmpty
                                          ? 'لا توجد نتائج مطابقة للبحث'
                                          : 'اختر الشركة (${filteredCompanies.length} شركة متاحة)',
                                      style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                    ),
                                    items: filteredCompanies.map((comp) {
                                      return DropdownMenuItem<String>(
                                        value: comp['slug'],
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                comp['name']!,
                                                style: GoogleFonts.cairo(
                                                  fontWeight: comp['slug'] == _selectedCompanySlug
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: colorScheme.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                comp['slug']!,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        final match = companies.firstWhere((c) => c['slug'] == value);
                                        setState(() {
                                          _selectedCompanySlug = match['slug'];
                                          _selectedCompanyName = match['name'];
                                        });
                                      }
                                    },
                                  ),
                                ),
                                if (_selectedCompanySlug != null) ...[
                                  const SizedBox(width: 10),
                                  IconButton.filledTonal(
                                    tooltip: 'إلغاء تحديد الشركة',
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _selectedCompanySlug = null;
                                        _selectedCompanyName = null;
                                      });
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.7),
                                      foregroundColor: colorScheme.onErrorContainer,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      padding: const EdgeInsets.all(16),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // 3. Quick-Pick matching chips when searching or when companies exist
                            if (searchQuery.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              if (filteredCompanies.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'لا توجد شركة باسم أو كود: "$searchQuery"',
                                    style: GoogleFonts.cairo(color: colorScheme.error, fontSize: 13),
                                  ),
                                )
                              else ...[
                                Text(
                                  'نتائج البحث المطابقة (${filteredCompanies.length}):',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: filteredCompanies.map((comp) {
                                    final isSelected = comp['slug'] == _selectedCompanySlug;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedCompanySlug = comp['slug'];
                                          _selectedCompanyName = comp['name'];
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primaryContainer
                                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isSelected ? Icons.check_circle : Icons.business,
                                              size: 16,
                                              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              comp['name']!,
                                              style: GoogleFonts.cairo(
                                                fontSize: 13,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? colorScheme.primary.withValues(alpha: 0.15)
                                                    : colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                comp['slug']!,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected ? colorScheme.primary : colorScheme.onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],

                            // 4. Selected Company Highlight Card
                            if (selectedCompany != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.verified, color: colorScheme.primary, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.cairo(color: colorScheme.onSurface, fontSize: 13),
                                          children: [
                                            const TextSpan(text: 'الشركة المحددة حالياً: '),
                                            TextSpan(
                                              text: selectedCompany['name'],
                                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.primary),
                                            ),
                                            const TextSpan(text: '  (كود: '),
                                            TextSpan(
                                              text: selectedCompany['slug'],
                                              style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: colorScheme.secondary),
                                            ),
                                            const TextSpan(text: ')'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Section 2: Add Gift Form
                if (_selectedCompanySlug != null)
                  _buildSectionCard(
                    context: context,
                    icon: Icons.add_box,
                    title: 'إضافة هدية جديدة',
                    subtitle: 'قم بإضافة هدية جديدة للمخزون',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _giftNameController,
                              focusNode: _giftNameFocusNode,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _giftQuantityFocusNode.requestFocus(),
                              style: GoogleFonts.cairo(),
                              decoration: InputDecoration(
                                labelText: 'اسم الهدية',
                                hintText: 'مثال: ساعة يد، تيشرت...',
                                labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _giftQuantityController,
                              focusNode: _giftQuantityFocusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _isLoading ? null : _addGift(),
                              style: GoogleFonts.cairo(),
                              decoration: InputDecoration(
                                labelText: 'الكمية',
                                hintText: 'مثال: 10',
                                labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                hintStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: _isLoading ? null : _addGift,
                            icon: _isLoading 
                                ? const SizedBox(
                                    width: 18, 
                                    height: 18, 
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.add, size: 20),
                            label: Text(
                              _isLoading ? 'جاري الإضافة...' : 'إضافة هدية',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                
                if (_selectedCompanySlug != null) const SizedBox(height: 24),

                // Section 3: Gifts Inventory
                if (_selectedCompanySlug != null)
                  _buildSectionCard(
                    context: context,
                    icon: Icons.inventory_2,
                    title: 'مخزون الهدايا',
                    subtitle: 'إدارة الهدايا المتوفرة للشركة المحددة',
                    children: [
                      StreamBuilder<QuerySnapshot>(
                        stream: firestore
                            .collection('company_gifts')
                            .where('companySlug', isEqualTo: _selectedCompanySlug?.toLowerCase().trim())
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Text('خطأ: ${snapshot.error}', style: GoogleFonts.cairo(color: colorScheme.error));
                          }

                          final gifts = snapshot.data?.docs ?? [];

                          if (gifts.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Text(
                                  'لا توجد هدايا مضافة لهذه الشركة بعد',
                                  style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: gifts.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final data = gifts[index].data() as Map<String, dynamic>;
                              data['id'] = gifts[index].id;
                              
                              final giftTitle = data['giftName'] ?? data['name'] ?? 'بدون اسم';
                              final availableQty = data['availableQuantity'] ?? 0;
                              final totalQty = data['totalQuantity'] ?? 0;
                              final isAvailable = availableQty > 0;
                              
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.card_giftcard, color: colorScheme.onSecondaryContainer),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            giftTitle,
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.secondaryContainer,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'الإجمالي: $totalQty',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 12,
                                                    color: colorScheme.onSecondaryContainer,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (totalQty - availableQty > 0) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    'مخصص بالحملات: ${totalQty - availableQty}',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 12,
                                                      color: Colors.orange.shade900,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isAvailable
                                                      ? Colors.green.withValues(alpha: 0.2)
                                                      : colorScheme.errorContainer,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'المتاح: $availableQty',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 12,
                                                    color: isAvailable
                                                        ? Colors.green[800]
                                                        : colorScheme.onErrorContainer,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.edit, size: 20),
                                      tooltip: 'تعديل الكمية المتاحة',
                                      onPressed: () => _showEditGiftDialog(data),
                                      style: IconButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.delete, size: 20),
                                      tooltip: 'حذف الهدية',
                                      onPressed: () => _deleteGift(data['id']),
                                      style: IconButton.styleFrom(
                                        backgroundColor: colorScheme.errorContainer,
                                        foregroundColor: colorScheme.onErrorContainer,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
