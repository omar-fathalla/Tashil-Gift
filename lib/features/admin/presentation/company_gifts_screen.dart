import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/services/company_gifts_service.dart';
import '../domain/campaign_wording.dart';
import '../domain/company_gift_model.dart';

/// Master Company Gifts & Prizes Catalog Screen (كتالوج هدايا وجوائز الشركات المعتمدة)
/// Exclusively for Super Admin to define, standardize, and maintain official master gifts
/// and vouchers for each company without manual stock/inventory friction.
class CompanyGiftsScreen extends ConsumerStatefulWidget {
  const CompanyGiftsScreen({super.key});

  @override
  ConsumerState<CompanyGiftsScreen> createState() => _CompanyGiftsScreenState();
}

class _CompanyGiftsScreenState extends ConsumerState<CompanyGiftsScreen> {
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  String? _selectedCompanySlug;
  String? _selectedCompanyName;
  String _selectedGiftType = 'product'; // 'product' | 'voucher'
  final TextEditingController _companySearchController = TextEditingController();
  final TextEditingController _giftNameController = TextEditingController();
  final TextEditingController _voucherUnitValueController = TextEditingController();
  final FocusNode _giftNameFocusNode = FocusNode();
  final FocusNode _voucherUnitValueFocusNode = FocusNode();
  bool _isLoading = false;

  // Optional Product Image Upload State
  Uint8List? _pickedImageBytes;
  String? _pickedImageFileName;

  // Memoized streams outside build() per Rule 9
  Stream<QuerySnapshot>? _companiesStream;
  String? _lastGiftsCompanySlug;
  Stream<QuerySnapshot>? _giftsStream;

  Stream<QuerySnapshot>? _getCompaniesStream(FirebaseFirestore? firestore) {
    if (firestore == null) return null;
    return _companiesStream ??= firestore.collection('companies').snapshots();
  }

  Stream<QuerySnapshot>? _getGiftsStream(FirebaseFirestore? firestore, String companySlug) {
    if (firestore == null) return null;
    final cleanSlug = companySlug.toLowerCase().trim();
    if (_lastGiftsCompanySlug != cleanSlug || _giftsStream == null) {
      _lastGiftsCompanySlug = cleanSlug;
      _giftsStream = firestore
          .collection('company_gifts')
          .where('companySlug', isEqualTo: cleanSlug)
          .snapshots();
    }
    return _giftsStream;
  }

  @override
  void dispose() {
    _companySearchController.dispose();
    _giftNameController.dispose();
    _voucherUnitValueController.dispose();
    _giftNameFocusNode.dispose();
    _voucherUnitValueFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickGiftImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _pickedImageBytes = file.bytes;
            _pickedImageFileName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء اختيار الصورة: ${AppErrorHandler.getFriendlyMessage(e)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _clearPickedImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageFileName = null;
    });
  }

  Future<String?> _uploadGiftImageIfNeeded(String companySlug) async {
    if (_pickedImageBytes == null) return null;
    try {
      final storage = ref.read(firebaseStorageProvider);
      final ext = _pickedImageFileName != null && _pickedImageFileName!.contains('.')
          ? _pickedImageFileName!.split('.').last.toLowerCase()
          : 'jpg';
      final cleanSlug = companySlug.isNotEmpty ? companySlug : 'general';
      final storagePath = 'company_gifts/$cleanSlug/${DateTime.now().millisecondsSinceEpoch}_gift.$ext';
      final storageRef = storage.ref().child(storagePath);
      final metadata = SettableMetadata(
        contentType: ext == 'png'
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg'),
        customMetadata: {
          'companySlug': cleanSlug,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );
      await storageRef.putData(_pickedImageBytes!, metadata).timeout(const Duration(seconds: 15));
      return await storageRef.getDownloadURL().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Error uploading gift image: $e');
      return null;
    }
  }

  void _showImagePreviewDialog(String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 450, maxHeight: 450),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filled(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGiftImagePickerBox(bool isAr, ColorScheme colorScheme) {
    final hasImage = _pickedImageBytes != null;
    return Tooltip(
      message: hasImage
          ? (isAr ? 'اضغط لتغيير الصورة' : 'Tap to change image')
          : (isAr ? 'إرفاق صورة المنتج (اختياري)' : 'Upload product image (optional)'),
      child: InkWell(
        onTap: _pickGiftImage,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: hasImage
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasImage
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: hasImage ? 1.5 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _pickedImageBytes!,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr ? 'صورة' : 'Image',
                      style: GoogleFonts.cairo(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              if (hasImage)
                PositionedDirectional(
                  top: 2,
                  end: 2,
                  child: InkWell(
                    onTap: _clearPickedImage,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onVoucherDenominationSelected(double val) {
    final valStr = val == val.roundToDouble() ? val.toInt().toString() : val.toString();
    _voucherUnitValueController.text = valStr;
    if (_giftNameController.text.isEmpty || _giftNameController.text.startsWith('فواتشر') || _giftNameController.text.startsWith('قسيمة')) {
      _giftNameController.text = 'فواتشر $valStr جنيه'; // C-06: stored value (server detects vouchers by this word)
    }
    setState(() {});
  }

  Future<void> _addGiftToCatalog() async {
    final isAr = ref.isArabic;

    if (_selectedCompanySlug == null || _selectedCompanySlug!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'يرجى اختيار الشركة أولاً' : 'Please select a company first',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    double unitVal = 0.0;
    String name = _giftNameController.text.trim();

    if (_selectedGiftType == 'voucher') {
      unitVal = _voucherUnitValueController.text.trim().toDoubleOrNull() ?? 0.0;
      if (unitVal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'يرجى تحديد القيمة المالية للكارت الواحد (فئة كارت المشتريات مثل 25، 50، 100 ج.م)'
                  : 'Please specify the voucher face value (e.g. 25, 50, 100 EGP)',
              style: GoogleFonts.cairo(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (name.isEmpty) {
        final valFormatted = unitVal == unitVal.roundToDouble() ? unitVal.toInt().toString() : unitVal.toString();
        name = isAr ? 'فواتشر $valFormatted جنيه' : 'Voucher $valFormatted EGP'; // C-06: stored value
      }
    } else {
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'يرجى إدخال اسم الهدية / المنتج' : 'Please enter the gift / product name',
              style: GoogleFonts.cairo(),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final slug = _selectedCompanySlug!.toLowerCase().trim();
      final companyName = _selectedCompanyName ?? _selectedCompanySlug!;

      String? uploadedImageUrl;
      if (_pickedImageBytes != null) {
        uploadedImageUrl = await _uploadGiftImageIfNeeded(slug);
      }

      await ref.read(companyGiftsServiceProvider).addGift(
        companySlug: slug,
        companyName: companyName,
        giftName: name,
        quantity: 0, // Master catalog definition (stock allocated at branch level by Manager)
        giftType: _selectedGiftType,
        unitValue: unitVal,
        imageUrl: uploadedImageUrl,
        addedBy: 'مسؤول النظام (الأدمن)',
      );

      _giftNameController.clear();
      _voucherUnitValueController.clear();
      _clearPickedImage();

      if (mounted) {
        if (_selectedGiftType == 'voucher') {
          _voucherUnitValueFocusNode.requestFocus();
        } else {
          _giftNameFocusNode.requestFocus();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedGiftType == 'voucher'
                        ? (isAr ? 'تمت إضافة كارت "$name" إلى الكتالوج المعتمد بنجاح' : 'Voucher "$name" added to catalog successfully')
                        : (isAr ? 'تمت إضافة الهدية "$name" إلى الكتالوج المعتمد بنجاح' : 'Gift "$name" added to catalog successfully'),
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: colorScheme.onTertiaryFixedVariant,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr ? 'خطأ أثناء الإضافة: ${AppErrorHandler.getFriendlyMessage(e)}' : 'Error adding gift: ${AppErrorHandler.getFriendlyMessage(e)}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
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

  void _showEditGiftDialog(CompanyGiftModel gift) {
    final TextEditingController editNameController = TextEditingController(text: gift.giftName);
    final rawUnitVal = gift.unitValue;
    final isVoucher = gift.isVoucher;
    final TextEditingController editUnitValController = TextEditingController(
      text: (isVoucher && rawUnitVal > 0)
          ? (rawUnitVal == rawUnitVal.roundToDouble() ? rawUnitVal.toInt().toString() : rawUnitVal.toString())
          : '',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isAr = ref.isArabic;

    Uint8List? editImageBytes;
    String? editImageFileName;
    String? currentImageUrl = gift.imageUrl;
    bool removeImage = false;
    bool isSavingEdit = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final hasAnyImage = !removeImage && (editImageBytes != null || (currentImageUrl != null && currentImageUrl.isNotEmpty));

            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAr ? 'تعديل بيانات الصنف في الكتالوج' : 'Edit Catalog Gift',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image Picker / Preview in Dialog
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: editImageBytes != null
                                      ? Image.memory(editImageBytes!, fit: BoxFit.cover)
                                      : (currentImageUrl != null && currentImageUrl.isNotEmpty && !removeImage
                                          ? Image.network(
                                              currentImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Icon(
                                                isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                                                size: 36,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            )
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.add_photo_alternate_outlined,
                                                  size: 32,
                                                  color: colorScheme.primary,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  isAr ? 'صورة المنتج' : 'Product Image',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            )),
                                ),
                              ),
                              if (hasAnyImage)
                                PositionedDirectional(
                                  top: -2,
                                  end: -2,
                                  child: InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        editImageBytes = null;
                                        editImageFileName = null;
                                        removeImage = true;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: colorScheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                                  withData: true,
                                );
                                if (res != null && res.files.isNotEmpty && res.files.first.bytes != null) {
                                  setDialogState(() {
                                    editImageBytes = res.files.first.bytes;
                                    editImageFileName = res.files.first.name;
                                    removeImage = false;
                                  });
                                }
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.photo_camera_rounded, size: 16),
                            label: Text(
                              hasAnyImage
                                  ? (isAr ? 'تغيير صورة الصنف' : 'Change Image')
                                  : (isAr ? 'رفع صورة الصنف (اختياري)' : 'Upload Image (Optional)'),
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    TextField(
                      controller: editNameController,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: isAr ? 'اسم الهدية / المنتج المعتمد *' : 'Gift / Product Name *',
                        labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (isVoucher) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: editUnitValController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                        style: GoogleFonts.cairo(),
                        decoration: InputDecoration(
                          labelText: isAr ? 'قيمة الكارت الواحد (فئة كارت المشتريات)' : 'Voucher Face Value',
                          hintText: 'مثال: 50',
                          prefixText: 'ج.م ',
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSavingEdit ? null : () => Navigator.of(dialogCtx).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
                ),
                FilledButton.icon(
                  icon: isSavingEdit
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: isSavingEdit
                      ? null
                      : () async {
                          final newName = editNameController.text.trim();
                          final unitVal = editUnitValController.text.trim().toDoubleOrNull() ?? rawUnitVal;
                          if (newName.isEmpty) return;

                          setDialogState(() => isSavingEdit = true);

                          try {
                            String? updatedImageUrl;
                            if (editImageBytes != null) {
                              final storage = ref.read(firebaseStorageProvider);
                              final ext = editImageFileName != null && editImageFileName!.contains('.')
                                  ? editImageFileName!.split('.').last.toLowerCase()
                                  : 'jpg';
                              final storagePath = 'company_gifts/${gift.companySlug}/${DateTime.now().millisecondsSinceEpoch}_gift.$ext';
                              final storageRef = storage.ref().child(storagePath);
                              final metadata = SettableMetadata(
                                contentType: ext == 'png'
                                    ? 'image/png'
                                    : (ext == 'webp' ? 'image/webp' : 'image/jpeg'),
                                customMetadata: {
                                  'companySlug': gift.companySlug,
                                  'uploadedAt': DateTime.now().toIso8601String(),
                                },
                              );
                              await storageRef.putData(editImageBytes!, metadata).timeout(const Duration(seconds: 15));
                              updatedImageUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 10));
                            }

                            await ref.read(companyGiftsServiceProvider).updateGiftDetails(
                              giftId: gift.id,
                              giftName: newName,
                              unitValue: isVoucher ? unitVal : null,
                              imageUrl: updatedImageUrl,
                              removeImage: removeImage,
                            );

                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                          } catch (e) {
                            debugPrint('Error updating gift details: $e');
                            setDialogState(() => isSavingEdit = false);
                          }
                        },
                  label: Text(
                    isSavingEdit ? (isAr ? 'جاري الحفظ...' : 'Saving...') : (isAr ? 'حفظ التعديلات' : 'Save Changes'),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteGift(String giftId) async {
    final isAr = ref.isArabic;
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(
            isAr ? 'تأكيد حذف الهدية من الكتالوج' : 'Confirm Catalog Deletion',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          content: Text(
            isAr
                ? 'هل أنت متأكد من رغبتك في حذف هذا الصنف من الكتالوج المعتمد؟ سيتم مسح مخصصاته من الفعاليات التابعة للشركة.'
                : 'Are you sure you want to delete this item from the master catalog? All related campaign allocations will be removed.',
            style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(isAr ? 'إلغاء' : 'Cancel', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isAr ? 'حذف الصنف' : 'Delete Item', style: GoogleFonts.cairo()),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await ref.read(companyGiftsServiceProvider).deleteGiftCascade(
          giftId: giftId,
          companySlug: _selectedCompanySlug,
          performedBy: 'مسؤول النظام (الأدمن)',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAr ? 'تم حذف الصنف من الكتالوج المعتمد بنجاح' : 'Gift deleted from catalog successfully',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: colorScheme.tertiary,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'خطأ أثناء الحذف: ${AppErrorHandler.getFriendlyMessage(e)}',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final isAr = ref.isArabic;
    final colorScheme = Theme.of(context).colorScheme;
    FirebaseFirestore? firestore;
    try {
      firestore = ref.watch(firestoreProvider);
    } catch (_) {
      firestore = null;
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Page Header Card
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        size: 32,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.giftsTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.giftsSubtitle,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Company Selector Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.business_rounded,
                            size: 20,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? 'تحديد الشركة' : 'Select Company',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              isAr ? 'اختر الشركة بالبحث عن طريق الاسم أو كود الشركة (Slug) أو من القائمة' : 'Select company by searching name or slug',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    StreamBuilder<QuerySnapshot>(
                      stream: _getCompaniesStream(firestore),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}', style: GoogleFonts.cairo(color: colorScheme.error));
                        }

                        final docs = snapshot.data?.docs ?? [];
                        final companies = docs.map((d) {
                          final data = d.data() as Map<String, dynamic>;
                          return {
                            'slug': (data['slug'] ?? d.id).toString(),
                            'name': (data['name'] ?? data['companyName'] ?? d.id).toString(),
                          };
                        }).toList();

                        final search = _companySearchController.text.trim().toLowerCase();
                        final filteredCompanies = companies.where((c) {
                          final s = c['slug']!.toLowerCase();
                          final n = c['name']!.toLowerCase();
                          return s.contains(search) || n.contains(search);
                        }).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Search Field
                            TextField(
                              controller: _companySearchController,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.cairo(),
                              decoration: InputDecoration(
                                hintText: isAr ? 'ابحث باسم الشركة أو كود الشركة (مثال: juhayna أو جهينة)...' : 'Search company name or slug...',
                                prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
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
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Dropdown / Quick Select
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCompanySlug != null && companies.any((c) => c['slug'] == _selectedCompanySlug)
                                  ? _selectedCompanySlug
                                  : null,
                              hint: Text(
                                filteredCompanies.isEmpty
                                    ? (isAr ? 'لا توجد نتائج مطابقة' : 'No matching companies')
                                    : (isAr ? 'أو اختر من القائمة المنسدلة (${filteredCompanies.length} شركة متاحة)' : 'Or pick from dropdown (${filteredCompanies.length} available)'),
                                style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                              ),
                              isExpanded: true,
                              items: filteredCompanies.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c['slug'],
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        c['name']!,
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          c['slug']!,
                                          style: GoogleFonts.cairo(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final match = companies.firstWhere((c) => c['slug'] == val);
                                  setState(() {
                                    _selectedCompanySlug = val;
                                    _selectedCompanyName = match['name'];
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),

                            if (_selectedCompanySlug != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      isAr
                                          ? 'الشركة المحددة حالياً: ${_selectedCompanyName ?? _selectedCompanySlug} (كود: $_selectedCompanySlug)'
                                          : 'Selected Company: ${_selectedCompanyName ?? _selectedCompanySlug} (Slug: $_selectedCompanySlug)',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      tooltip: isAr ? 'إلغاء التحديد' : 'Clear selection',
                                      onPressed: () {
                                        setState(() {
                                          _selectedCompanySlug = null;
                                          _selectedCompanyName = null;
                                        });
                                      },
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
              ),

              const SizedBox(height: 24),

              // 3. Add Gift / Voucher Form Card
              if (_selectedCompanySlug != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.add_box_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.addGiftCardTitle,
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                isAr
                                    ? 'قم بتعريف هدية مادية أو كارت مشتريات نقدي لكتالوج الشركة المعتمد'
                                    : 'Define a physical gift or cash voucher for the master catalog',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Segmented Button: Product vs Voucher
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                              value: 'product',
                              label: Text(
                                isAr ? '🎁 منتج مادي (Product)' : '🎁 Physical Product',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                            ),
                            ButtonSegment<String>(
                              value: 'voucher',
                              label: Text(
                                isAr ? '💳 كارت مشتريات نقدي' : '💳 Cash Voucher',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          selected: {_selectedGiftType},
                          onSelectionChanged: (newSet) {
                            setState(() {
                              _selectedGiftType = newSet.first;
                              if (_selectedGiftType == 'voucher' && _voucherUnitValueController.text.isNotEmpty) {
                                final parsed = _voucherUnitValueController.text.toDoubleOrNull();
                                if (parsed != null) _onVoucherDenominationSelected(parsed);
                              }
                            });
                          },
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: colorScheme.primaryContainer,
                            selectedForegroundColor: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_selectedGiftType == 'voucher') ...[
                        // Quick Voucher Denomination Chips
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              isAr ? 'فئات سريعة للكارت الواحد:' : 'Quick Denominations:',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                            ),
                            ...[25, 50, 100, 200, 500].map((val) {
                              final isSel = _voucherUnitValueController.text == val.toString();
                              return ChoiceChip(
                                label: Text('$val ج.م', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                                selected: isSel,
                                selectedColor: colorScheme.primaryContainer,
                                checkmarkColor: colorScheme.onPrimaryContainer,
                                onSelected: (_) => _onVoucherDenominationSelected(val.toDouble()),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Input fields for voucher
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildGiftImagePickerBox(isAr, colorScheme),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _voucherUnitValueController,
                                focusNode: _voucherUnitValueFocusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [const ArabicToEnglishDigitsFormatter.digitsOnly()],
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _giftNameFocusNode.requestFocus(),
                                onChanged: (val) {
                                  if (_giftNameController.text.isEmpty || _giftNameController.text.startsWith('فواتشر')) {
                                    if (val.trim().isNotEmpty) {
                                      _giftNameController.text = 'فواتشر ${val.trim()} جنيه'; // C-06: stored value
                                    }
                                  }
                                  setState(() {});
                                },
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: isAr ? 'قيمة الكارت الواحد (الفئة) *' : 'Voucher Face Value *',
                                  hintText: 'مثال: 50',
                                  prefixText: 'ج.م ',
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: TextField(
                                controller: _giftNameController,
                                focusNode: _giftNameFocusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _isLoading ? null : _addGiftToCatalog(),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: isAr ? 'اسم كارت المشتريات المعتمد' : 'Voucher Display Name',
                                  hintText: isAr ? 'مثال: فواتشر 50 جنيه' : 'e.g. Voucher 50 EGP', // C-06: stored value (the saved name)
                                  labelStyle: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _isLoading ? null : _addGiftToCatalog,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.add_card_rounded, size: 20),
                              label: Text(
                                _isLoading ? (isAr ? 'جاري...' : 'Saving...') : (isAr ? 'إضافة كارت المشتريات للكتالوج' : 'Add to Catalog'),
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Input fields for standard physical product
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildGiftImagePickerBox(isAr, colorScheme),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 6,
                              child: TextField(
                                controller: _giftNameController,
                                focusNode: _giftNameFocusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _isLoading ? null : _addGiftToCatalog(),
                                style: GoogleFonts.cairo(),
                                decoration: InputDecoration(
                                  labelText: isAr ? 'اسم الهدية / المنتج المعتمد *' : 'Master Gift / Product Name *',
                                  hintText: isAr ? 'مثال: شامبو كلير 90 مل، تريزيمي 250 مل...' : 'e.g. Clear Shampoo 90ml...',
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
                              onPressed: _isLoading ? null : _addGiftToCatalog,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.add_circle_rounded, size: 20),
                              label: Text(
                                _isLoading ? (isAr ? 'جاري...' : 'Saving...') : (isAr ? 'إضافة الهدية للكتالوج' : 'Add to Catalog'),
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. Master Gifts Catalog List Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.inventory_2_rounded,
                              size: 20,
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.registeredGiftsTableTitle,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  isAr
                                      ? 'الأصناف والجوائز المعرفة رسمياً (اسحب الصنف لإعادة ترتيب الظهور)'
                                      : 'Official master gifts & prizes (drag to reorder appearance)',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot>(
                        stream: _getGiftsStream(firestore, _selectedCompanySlug!),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error: ${snapshot.error}',
                                style: GoogleFonts.cairo(color: colorScheme.error),
                              ),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.outlineVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      isAr
                                          ? 'لا توجد هدايا مضافة لكتالوج هذه الشركة بعد، يمكنك إضافة هدية من النموذج أعلاه'
                                          : 'No gifts added to master catalog yet. You can add a gift using the form above',
                                      style: GoogleFonts.cairo(color: colorScheme.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Convert docs to CompanyGiftModel and sort by orderIndex ascending
                          final gifts = docs.map((doc) => CompanyGiftModel.fromFirestore(doc)).toList();
                          gifts.sort((a, b) {
                            if (a.orderIndex != b.orderIndex) {
                              return a.orderIndex.compareTo(b.orderIndex);
                            }
                            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            return bTime.compareTo(aTime);
                          });

                          return ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: gifts.length,
                            proxyDecorator: (Widget child, int index, Animation<double> animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (BuildContext context, Widget? child) {
                                  final double animValue = Curves.easeInOut.transform(animation.value);
                                  final double scale = lerpDouble(1.0, 1.025, animValue)!;
                                  final double elevation = lerpDouble(0, 10, animValue)!;
                                  return Transform.scale(
                                    scale: scale,
                                    child: Material(
                                      elevation: elevation,
                                      color: Colors.transparent,
                                      shadowColor: colorScheme.primary.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(16),
                                      child: child,
                                    ),
                                  );
                                },
                                child: child,
                              );
                            },
                            onReorder: (int oldIndex, int newIndex) async {
                              HapticFeedback.mediumImpact();
                              if (oldIndex < newIndex) {
                                newIndex -= 1;
                              }
                              final movedItem = gifts.removeAt(oldIndex);
                              gifts.insert(newIndex, movedItem);

                              final firestoreInstance = ref.read(firestoreProvider);
                              try {
                                final batch = firestoreInstance.batch();
                                for (int i = 0; i < gifts.length; i++) {
                                  final docRef = firestoreInstance.collection('company_gifts').doc(gifts[i].id);
                                  batch.update(docRef, {'orderIndex': i});
                                }
                                await batch.commit();
                              } catch (e) {
                                debugPrint('Error updating gift order: $e');
                              }
                            },
                            itemBuilder: (context, index) {
                              final gift = gifts[index];
                              final giftTitle = gift.giftName.isNotEmpty ? CampaignWording.giftLabel(gift.giftName) : 'بدون اسم';
                              final rawUnitVal = gift.unitValue;
                              final isVoucher = gift.isVoucher;

                              return Padding(
                                key: ValueKey(gift.id),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ReorderableDelayedDragStartListener(
                                  index: index,
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isVoucher
                                          ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.6)
                                          : colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isVoucher
                                            ? colorScheme.primary.withValues(alpha: 0.3)
                                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                        width: isVoucher ? 1.5 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.shadow.withValues(alpha: 0.03),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // 1. Drag Handle
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Tooltip(
                                            message: strings.dragToReorderHint,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  Icons.drag_indicator_rounded,
                                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // 2. Gift Icon or Image Thumbnail
                                        if (gift.imageUrl != null && gift.imageUrl!.isNotEmpty)
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: GestureDetector(
                                              onTap: () => _showImagePreviewDialog(gift.imageUrl!, giftTitle),
                                              child: Tooltip(
                                                message: isAr ? 'اضغط لتكبير صورة المنتج' : 'Tap to view full image',
                                                child: Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: isVoucher
                                                          ? colorScheme.primary.withValues(alpha: 0.4)
                                                          : colorScheme.outlineVariant.withValues(alpha: 0.6),
                                                      width: 1.2,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.04),
                                                        blurRadius: 4,
                                                        offset: const Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(11),
                                                    child: Image.network(
                                                      gift.imageUrl!,
                                                      width: 48,
                                                      height: 48,
                                                      fit: BoxFit.cover,
                                                      loadingBuilder: (context, child, loadingProgress) {
                                                        if (loadingProgress == null) return child;
                                                        return Container(
                                                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                                          child: const Center(
                                                            child: SizedBox(
                                                              width: 16,
                                                              height: 16,
                                                              child: CircularProgressIndicator(strokeWidth: 2),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      errorBuilder: (context, error, stackTrace) => Container(
                                                        color: colorScheme.surfaceContainerHighest,
                                                        child: Icon(
                                                          isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard,
                                                          color: colorScheme.onSurfaceVariant,
                                                          size: 22,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: isVoucher
                                                  ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                                                  : colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard,
                                              color: isVoucher ? colorScheme.primary : colorScheme.onSecondaryContainer,
                                              size: 22,
                                            ),
                                          ),
                                        const SizedBox(width: 14),

                                        // 3. Name & Type Badge
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      giftTitle,
                                                      style: GoogleFonts.cairo(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: colorScheme.onSurface,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isVoucher)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.primaryContainer,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(
                                                        'فئة ${rawUnitVal == rawUnitVal.roundToDouble() ? rawUnitVal.toInt() : rawUnitVal} ج.م',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: colorScheme.onPrimaryContainer,
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.surfaceContainerHighest,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        isAr ? 'منتج مادي معتمد' : 'Physical Product',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // 4. Edit & Delete Actions
                                        IconButton.filledTonal(
                                          icon: const Icon(Icons.edit_rounded, size: 18),
                                          tooltip: isAr ? 'تعديل بيانات الصنف بالكتالوج' : 'Edit Catalog Item',
                                          onPressed: () => _showEditGiftDialog(gift),
                                          style: IconButton.styleFrom(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton.filledTonal(
                                          icon: const Icon(Icons.delete_rounded, size: 18),
                                          tooltip: isAr ? 'حذف الصنف من الكتالوج' : 'Delete from Catalog',
                                          onPressed: () => _deleteGift(gift.id),
                                          style: IconButton.styleFrom(
                                            backgroundColor: colorScheme.errorContainer,
                                            foregroundColor: colorScheme.onErrorContainer,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
