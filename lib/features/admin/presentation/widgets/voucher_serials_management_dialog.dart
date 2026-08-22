import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/firebase_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import '../../../admin/domain/event_model.dart';

/// Item representing a claimed voucher card record
class ClaimedVoucherCardRecord {
  final String serial;
  final String giftName;
  final double unitValue;
  final String branchName;
  final String customerName;
  final String customerPhone;
  final DateTime? claimedAt;
  final String transactionId;

  ClaimedVoucherCardRecord({
    required this.serial,
    required this.giftName,
    required this.unitValue,
    required this.branchName,
    required this.customerName,
    required this.customerPhone,
    required this.claimedAt,
    required this.transactionId,
  });
}

/// Advanced Material Design 3 Dialog for Managing, Auditing, and Resetting Voucher Serials
class VoucherSerialsManagementDialog extends ConsumerStatefulWidget {
  final EventModel event;

  const VoucherSerialsManagementDialog({
    super.key,
    required this.event,
  });

  /// Static helper to display the dialog smoothly with M3 transition
  static Future<void> show(BuildContext context, EventModel event) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'VoucherSerialsManagementDialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return VoucherSerialsManagementDialog(event: event);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutCubic,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<VoucherSerialsManagementDialog> createState() => _VoucherSerialsManagementDialogState();
}

class _VoucherSerialsManagementDialogState extends ConsumerState<VoucherSerialsManagementDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isResetting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleResetSerials(AppStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Icon(Icons.warning_amber_rounded, size: 40, color: Colors.amber.shade800),
          title: Text(
            strings.resetVoucherSerialsConfirmTitle,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          content: Text(
            strings.resetVoucherSerialsConfirmMsg,
            style: GoogleFonts.cairo(fontSize: 13.5, height: 1.5),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                strings.cancel,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                strings.confirm,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isResetting = true);
    try {
      final firestore = ref.read(firestoreProvider);
      await firestore.collection('events').doc(widget.event.id).update({
        'voucher_serials_reset_at': DateTime.now().toIso8601String(),
        'voucher_serials_last_reset_by': 'Admin',
      });

      if (!mounted) return;
      setState(() => _isResetting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.voucherSerialsResetSuccess,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء إعادة التعيين: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;

    Stream<QuerySnapshot<Map<String, dynamic>>>? transactionsStream;
    try {
      final firestore = ref.watch(firestoreProvider);
      if (widget.event.id.isNotEmpty) {
        transactionsStream = firestore
            .collection('receipts_transactions')
            .where('event_id', isEqualTo: widget.event.id)
            .snapshots();
      }
    } catch (_) {}

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 22 : 28),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 16 : 32,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: mediaQuery.size.height * 0.88,
          ),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: transactionsStream,
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];

              // Extract all claimed voucher cards
              final List<ClaimedVoucherCardRecord> records = [];

              for (final doc in docs) {
                final data = doc.data();
                if (data['status'] == 'rejected' || data['is_valid'] == false) continue;

                final bName = (data['branch_detected'] ?? data['branch'] ?? data['branch_id'] ?? '').toString();
                final cName = (data['customerName'] ?? data['customer_name'] ?? '').toString();
                final cPhone = (data['customerPhone'] ?? data['phone'] ?? '').toString();

                final rawDate = data['claimed_at'] ?? data['created_at'] ?? data['timestamp'];
                DateTime? dt;
                if (rawDate is Timestamp) {
                  dt = rawDate.toDate();
                } else if (rawDate is String) {
                  dt = DateTime.tryParse(rawDate);
                }

                // 1. Check claimed_gifts structure
                final claimedGifts = (data['claimed_gifts'] as List?) ?? [];
                for (final cg in claimedGifts) {
                  if (cg is Map) {
                    final isVoucher = cg['isVoucher'] == true || cg['is_voucher'] == true;
                    final gName = (cg['giftName'] ?? cg['gift_name'] ?? '').toString();
                    final uVal = (cg['unitValue'] ?? cg['unit_value'] as num?)?.toDouble() ?? 0.0;
                    final serials = List<String>.from(cg['serials'] ?? []);

                    if (isVoucher && serials.isNotEmpty) {
                      for (final s in serials) {
                        records.add(ClaimedVoucherCardRecord(
                          serial: s,
                          giftName: gName,
                          unitValue: uVal,
                          branchName: bName,
                          customerName: cName,
                          customerPhone: cPhone,
                          claimedAt: dt,
                          transactionId: doc.id,
                        ));
                      }
                    }
                  }
                }

                // 2. Fallback to root voucher_serials if claimed_gifts had none
                final rootSerials = List<String>.from(data['voucher_serials'] ?? []);
                if (rootSerials.isNotEmpty && records.where((r) => r.transactionId == doc.id).isEmpty) {
                  for (final s in rootSerials) {
                    records.add(ClaimedVoucherCardRecord(
                      serial: s,
                      giftName: (data['prize_won'] ?? 'فواتشر مشتريات').toString(),
                      unitValue: (data['unit_value'] as num?)?.toDouble() ?? 0.0,
                      branchName: bName,
                      customerName: cName,
                      customerPhone: cPhone,
                      claimedAt: dt,
                      transactionId: doc.id,
                    ));
                  }
                }
              }

              // Filter by search query
              final filtered = _searchQuery.trim().isEmpty
                  ? records
                  : records.where((r) {
                      final q = _searchQuery.trim().toLowerCase();
                      return r.serial.toLowerCase().contains(q) ||
                          r.customerName.toLowerCase().contains(q) ||
                          r.customerPhone.contains(q) ||
                          r.branchName.toLowerCase().contains(q) ||
                          r.giftName.toLowerCase().contains(q);
                    }).toList();

              // Sort by date descending
              filtered.sort((a, b) {
                if (a.claimedAt == null) return 1;
                if (b.claimedAt == null) return -1;
                return b.claimedAt!.compareTo(a.claimedAt!);
              });

              final totalCards = records.length;
              final totalValue = records.fold<double>(0.0, (acc, r) => acc + r.unitValue);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 14 : 20,
                      isMobile ? 14 : 18,
                      isMobile ? 8 : 12,
                      isMobile ? 8 : 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB300), Color(0xFFFF6D00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF8F00).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.confirmation_number_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                strings.voucherSerialsManagementTitle,
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 15.5 : 17.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.event.eventName} (${widget.event.targetCompany})',
                                style: GoogleFonts.cairo(
                                  fontSize: isMobile ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          tooltip: strings.close,
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // 2. Summary & Search Controls
                  Padding(
                    padding: EdgeInsets.all(isMobile ? 14 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // KPI Bar
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.amber.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.credit_card_rounded, size: 20, color: Colors.amber.shade900),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            strings.totalClaimedVoucherCards,
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                          Text(
                                            '$totalCards كارت مسجل',
                                            style: GoogleFonts.cairo(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (totalValue > 0) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.payments_rounded, size: 20, color: colorScheme.primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'إجمالي القيمة المالية',
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                            Text(
                                              '${totalValue.toInt()} ج.م',
                                              style: GoogleFonts.cairo(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Search Input Field
                        TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.toEnglishDigits(convertDecimal: false);
                            });
                          },
                          decoration: InputDecoration(
                            hintText: strings.searchVoucherSerialPlaceholder,
                            hintStyle: GoogleFonts.cairo(fontSize: 12.5),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Scrollable List of Voucher Records
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.confirmation_number_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                  const SizedBox(height: 10),
                                  Text(
                                    strings.noVouchersClaimedYet,
                                    style: GoogleFonts.cairo(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    // Serial Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.amber.shade300),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.qr_code_rounded, size: 14, color: Colors.amber.shade900),
                                          const SizedBox(width: 6),
                                          SelectableText(
                                            item.serial,
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.giftName,
                                                  style: GoogleFonts.cairo(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.unitValue > 0) ...[
                                                Text(
                                                  '${item.unitValue.toInt()} ج.م',
                                                  style: GoogleFonts.cairo(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12.5,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.branchName.isNotEmpty ? item.branchName : "الفرع العام"} • ${item.customerName.isNotEmpty ? item.customerName : "عميل"} (${item.customerPhone.isNotEmpty ? item.customerPhone : "بدون هاتف"})',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Date
                                    if (item.claimedAt != null)
                                      Text(
                                        '${item.claimedAt!.day}/${item.claimedAt!.month} ${item.claimedAt!.hour.toString().padLeft(2, '0')}:${item.claimedAt!.minute.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10.5,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  const Divider(height: 1),

                  // 4. Footer with Reset Action Button
                  Padding(
                    padding: EdgeInsets.all(isMobile ? 14 : 18),
                    child: Row(
                      children: [
                        // Admin Reset Action Button
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isResetting ? null : () => _handleResetSerials(strings),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: _isResetting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.restart_alt_rounded, size: 20),
                            label: Text(
                              strings.resetVoucherSerialsBtn,
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Close Button
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            strings.close,
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
