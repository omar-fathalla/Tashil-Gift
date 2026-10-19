import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../../../core/utils/file_download_helper.dart';
import '../../domain/customer_marketing_service.dart';
import '../../domain/marketing_contact_model.dart';
import '../../domain/whatsapp_gateway_service.dart';

enum _ImportDialogTab { manual, excel }

/// Modal dialog providing:
/// 1. Manual single customer entry with branch and notes.
/// 2. Bulk Excel/CSV import with smart column mapping, live preview, and sample template download.
class CustomerImportDialog extends StatefulWidget {
  final String companySlug;
  final String companyName;
  final List<String> availableBranches;
  final AppStrings strings;
  final bool isAr;
  final Function(List<MarketingContactModel> importedContacts)? onImported;
  final void Function(int count)? onImportSuccess;

  const CustomerImportDialog({
    super.key,
    required this.companySlug,
    required this.companyName,
    required this.availableBranches,
    required this.strings,
    required this.isAr,
    this.onImported,
    this.onImportSuccess,
  });

  @override
  State<CustomerImportDialog> createState() => _CustomerImportDialogState();
}

class _CustomerImportDialogState extends State<CustomerImportDialog> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  final CustomerMarketingService _service = CustomerMarketingService();
  _ImportDialogTab _activeTab = _ImportDialogTab.manual;

  // --- Manual Entry State ---
  final _manualNameController = TextEditingController();
  final _manualPhoneController = TextEditingController();
  final _manualBranchController = TextEditingController();
  final _manualNotesController = TextEditingController();
  bool _isSavingManual = false;

  // --- Excel Import State ---
  bool _isParsingFile = false;
  bool _isSavingBatch = false;
  String? _pickedFileName;
  CustomerImportParseResult? _parseResult;

  @override
  void dispose() {
    _manualNameController.dispose();
    _manualPhoneController.dispose();
    _manualBranchController.dispose();
    _manualNotesController.dispose();
    super.dispose();
  }

  // --- Actions ---

  Future<void> _handleSaveManual() async {
    final rawName = _manualNameController.text.trim();
    final rawPhone = _manualPhoneController.text.trim().toEnglishDigits();
    final cleanPhone = WhatsAppGatewayService.formatInternationalPhone(rawPhone);

    if (cleanPhone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAr ? 'برجاء إدخال رقم هاتف صحيح' : 'Please enter a valid phone number'),
          backgroundColor: colorScheme.onErrorContainer,
        ),
      );
      return;
    }

    setState(() => _isSavingManual = true);

    final contact = MarketingContactModel(
      id: '${widget.companySlug}_$cleanPhone',
      name: rawName.isNotEmpty ? rawName : (widget.isAr ? 'عميل مسجل' : 'Registered Customer'),
      rawPhone: rawPhone,
      cleanPhone: cleanPhone,
      branch: _manualBranchController.text.trim(),
      companySlug: widget.companySlug,
      source: 'manual',
      notes: _manualNotesController.text.trim(),
      createdAt: DateTime.now(),
    );

    final success = await _service.saveContact(contact);

    if (mounted) {
      setState(() => _isSavingManual = false);
      if (success) {
        widget.onImported?.call([contact]);
        widget.onImportSuccess?.call(1);
        Navigator.of(context).pop([contact]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.strings.customerAddedSuccess),
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isAr ? 'فشل حفظ العميل في قاعدة البيانات' : 'Failed to save customer'),
            backgroundColor: colorScheme.onErrorContainer,
          ),
        );
      }
    }
  }

  Future<void> _pickAndParseExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      setState(() {
        _isParsingFile = true;
        _pickedFileName = file.name;
        _parseResult = null;
      });

      final parsed = await _service.parseExcelOrCsv(
        bytes: bytes,
        fileName: file.name,
        companySlug: widget.companySlug,
      );

      if (mounted) {
        setState(() {
          _isParsingFile = false;
          _parseResult = parsed;
        });

        if (parsed.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.strings.fileParsedSuccessfully}: ${parsed.validContacts.length} ${widget.strings.validNumbersCount}'),
              backgroundColor: colorScheme.tertiary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (parsed.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(parsed.errorMessage!),
              backgroundColor: colorScheme.onErrorContainer,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isParsingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء قراءة الملف: $e'),
            backgroundColor: colorScheme.onErrorContainer,
          ),
        );
      }
    }
  }

  Future<void> _handleConfirmBatchImport() async {
    if (_parseResult == null || _parseResult!.validContacts.isEmpty) return;

    setState(() => _isSavingBatch = true);

    final savedCount = await _service.saveBatchContacts(_parseResult!.validContacts);

    if (mounted) {
      setState(() => _isSavingBatch = false);
      if (savedCount > 0) {
        widget.onImported?.call(_parseResult!.validContacts);
        widget.onImportSuccess?.call(savedCount);
        Navigator.of(context).pop(_parseResult!.validContacts);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.strings.customersImportedSuccess} ($savedCount)'),
            backgroundColor: colorScheme.tertiary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isAr ? 'فشل استيراد العملاء' : 'Failed to import customers'),
            backgroundColor: colorScheme.onErrorContainer,
          ),
        );
      }
    }
  }

  void _downloadTemplate() {
    final bytes = CustomerMarketingService.generateSampleExcelTemplate();
    downloadFileBytes(
      bytes: bytes,
      fileName: 'Tashil_Customers_Sample_Template.xlsx',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isAr ? 'تم تنزيل نموذج الإكسيل التجريبي بنجاح ✅' : 'Sample Excel template downloaded successfully ✅'),
        backgroundColor: colorScheme.tertiary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Dialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.onTertiaryContainer,
                      colorScheme.tertiary,
                      colorScheme.tertiary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.strings.customerImportTitle,
                            style: GoogleFonts.cairo(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            widget.companyName.isNotEmpty ? widget.companyName : widget.strings.customerImportSubtitle,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Tab Selector
              Container(
                padding: const EdgeInsets.all(8),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        tab: _ImportDialogTab.manual,
                        label: widget.strings.addSingleCustomer,
                        icon: Icons.person_add_rounded,
                        cs: cs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTabButton(
                        tab: _ImportDialogTab.excel,
                        label: widget.strings.importExcelBulk,
                        icon: Icons.upload_file_rounded,
                        cs: cs,
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _activeTab == _ImportDialogTab.manual
                    ? _buildManualEntryView(cs, isMobile)
                    : _buildExcelImportView(cs, isMobile),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required _ImportDialogTab tab,
    required String label,
    required IconData icon,
    required ColorScheme cs,
  }) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? colorScheme.tertiary : cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.onTertiaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Manual Entry View ---
  Widget _buildManualEntryView(ColorScheme cs, bool isMobile) {
    final rawPhone = _manualPhoneController.text.trim().toEnglishDigits();
    final cleanPhone = WhatsAppGatewayService.formatInternationalPhone(rawPhone);
    final isValidPhone = cleanPhone.length >= 9;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name Field
          Text(widget.strings.customerNameField, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _manualNameController,
            decoration: InputDecoration(
              hintText: widget.isAr ? 'مثال: أحمد محمود' : 'e.g. Ahmed Mahmoud',
              hintStyle: GoogleFonts.cairo(fontSize: 12),
              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            style: GoogleFonts.cairo(fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Phone Field
          Text(widget.strings.customerPhoneField, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _manualPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: widget.isAr ? '010XXXXXXXX أو 2010XXXXXXXX' : '010XXXXXXXX',
              hintStyle: GoogleFonts.robotoMono(fontSize: 12),
              prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20, color: colorScheme.tertiary),
              suffixIcon: isValidPhone
                  ? Icon(Icons.check_circle_rounded, color: colorScheme.tertiary, size: 20)
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              helperText: isValidPhone ? 'WhatsApp ID: +$cleanPhone' : null,
              helperStyle: GoogleFonts.robotoMono(fontSize: 11, color: colorScheme.tertiary),
            ),
            style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w600),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Branch Field
          Text(widget.strings.branchNameCol, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (widget.availableBranches.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: widget.availableBranches.contains(_manualBranchController.text) ? _manualBranchController.text : null,
              decoration: InputDecoration(
                hintText: widget.isAr ? 'اختر الفرع التابع له...' : 'Select branch...',
                hintStyle: GoogleFonts.cairo(fontSize: 12),
                prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: widget.availableBranches
                  .where((b) => b != 'all')
                  .map((b) => DropdownMenuItem(value: b, child: Text(b, style: GoogleFonts.cairo(fontSize: 13))))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  _manualBranchController.text = val;
                }
              },
            )
          else
            TextField(
              controller: _manualBranchController,
              decoration: InputDecoration(
                hintText: widget.isAr ? 'اسم الفرع أو المدينة (اختياري)' : 'Branch or City (optional)',
                hintStyle: GoogleFonts.cairo(fontSize: 12),
                prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              style: GoogleFonts.cairo(fontSize: 13),
            ),
          const SizedBox(height: 16),

          // Notes Field
          Text(widget.isAr ? 'ملاحظات / وسوم (اختياري)' : 'Notes / Tags (Optional)', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _manualNotesController,
            decoration: InputDecoration(
              hintText: widget.isAr ? 'مثال: عميل VIP، مهتم بمنتجات الألبان' : 'e.g. VIP Customer, interested in dairy',
              hintStyle: GoogleFonts.cairo(fontSize: 12),
              prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            style: GoogleFonts.cairo(fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Submit Button
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.tertiary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isSavingManual
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _isSavingManual ? (widget.isAr ? 'جاري الحفظ...' : 'Saving...') : widget.strings.confirmImportCustomers,
                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: (!isValidPhone || _isSavingManual) ? null : _handleSaveManual,
            ),
          ),
        ],
      ),
    );
  }

  // --- Excel Import View ---
  Widget _buildExcelImportView(ColorScheme cs, bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Download Sample Template Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.file_download_rounded, color: colorScheme.tertiary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.strings.downloadExcelTemplate,
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onTertiaryContainer),
                      ),
                      Text(
                        widget.isAr
                            ? 'قم بتنزيل النموذج وتعبئة الأسماء والأرقام لرفعه مباشرة'
                            : 'Download the template, fill names and numbers, and upload directly',
                        style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.tertiary,
                    side: BorderSide(color: colorScheme.tertiary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _downloadTemplate,
                  child: Text(widget.isAr ? 'تنزيل النموذج' : 'Download', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // File Picker Dropzone Card
          InkWell(
            onTap: _isParsingFile ? null : _pickAndParseExcel,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pickedFileName != null ? colorScheme.tertiary : cs.outlineVariant,
                  width: _pickedFileName != null ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isParsingFile)
                    CircularProgressIndicator(color: colorScheme.tertiary)
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.table_chart_rounded, size: 32, color: colorScheme.tertiary),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    _pickedFileName ?? widget.strings.selectExcelOrCsvFile,
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isAr ? 'صيغ الملفات المدعومة: .xlsx, .xls, .csv' : 'Supported formats: .xlsx, .xls, .csv',
                    style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Parsed Results Stats & Preview
          if (_parseResult != null) ...[
            // KPI Summary Row
            Row(
              children: [
                Expanded(
                  child: _buildStatBadge(
                    label: widget.strings.validNumbersCount,
                    count: _parseResult!.validContacts.length,
                    color: colorScheme.tertiary,
                    icon: Icons.check_circle_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBadge(
                    label: widget.strings.invalidNumbersCount,
                    count: _parseResult!.invalidRowsCount,
                    color: colorScheme.onErrorContainer,
                    icon: Icons.error_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBadge(
                    label: widget.strings.duplicateNumbersCount,
                    count: _parseResult!.duplicateCount,
                    color: colorScheme.onSecondaryFixedVariant,
                    icon: Icons.filter_alt_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Preview Table of first items
            if (_parseResult!.validContacts.isNotEmpty) ...[
              Text(
                widget.isAr
                    ? 'معاينة جهات الاتصال المستخرجة (أول ${_parseResult!.validContacts.take(5).length} من ${_parseResult!.validContacts.length}):'
                    : 'Extracted Contacts Preview (First ${_parseResult!.validContacts.take(5).length} of ${_parseResult!.validContacts.length}):',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: _parseResult!.validContacts.take(5).map((c) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_pin_circle_rounded, size: 18, color: colorScheme.tertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Text(
                                c.name,
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '+${c.cleanPhone}',
                                style: GoogleFonts.robotoMono(fontSize: 12, color: colorScheme.onTertiaryContainer),
                              ),
                            ),
                            if (c.branch.isNotEmpty)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  c.branch,
                                  style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Confirm Import Button
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.tertiary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isSavingBatch
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 20),
                  label: Text(
                    _isSavingBatch
                        ? (widget.isAr ? 'جاري الاستيراد والحفظ...' : 'Importing...')
                        : '${widget.strings.confirmImportCustomers} (${_parseResult!.validContacts.length})',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSavingBatch ? null : _handleConfirmBatchImport,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatBadge({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.cairo(fontSize: 10, color: color),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
