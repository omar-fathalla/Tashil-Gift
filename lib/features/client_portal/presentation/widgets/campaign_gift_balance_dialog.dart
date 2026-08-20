import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/firebase_service.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../admin/domain/event_model.dart';

/// Interactive Material Design 3 Dialog displaying real-time Campaign Gifts & Branch Stock Balance
class CampaignGiftBalanceDialog extends ConsumerStatefulWidget {
  final EventModel event;

  const CampaignGiftBalanceDialog({
    super.key,
    required this.event,
  });

  /// Static helper to display the dialog smoothly with M3 transitions
  static Future<void> show(BuildContext context, EventModel event) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CampaignGiftBalanceDialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return CampaignGiftBalanceDialog(event: event);
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
  ConsumerState<CampaignGiftBalanceDialog> createState() => _CampaignGiftBalanceDialogState();
}

class _CampaignGiftBalanceDialogState extends ConsumerState<CampaignGiftBalanceDialog> {
  String? _selectedBranchKey;
  String? _pinnedBranchKey;

  @override
  void initState() {
    super.initState();
    _loadSavedBranch();
  }

  Future<void> _loadSavedBranch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedForEvent = prefs.getString('pinned_branch_event_${widget.event.id}');
      final savedGlobal = prefs.getString('pinned_branch_global');
      final effectiveSaved = (savedForEvent != null && savedForEvent.isNotEmpty)
          ? savedForEvent
          : savedGlobal;

      if (mounted && effectiveSaved != null && effectiveSaved.isNotEmpty) {
        setState(() {
          _selectedBranchKey = effectiveSaved;
          _pinnedBranchKey = effectiveSaved;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePinnedBranch(String branchKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pinned_branch_event_${widget.event.id}', branchKey);
      await prefs.setString('pinned_branch_global', branchKey);
      if (mounted) {
        setState(() {
          _pinnedBranchKey = branchKey;
        });
      }
    } catch (_) {}
  }

  Future<void> _clearPinnedBranch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pinned_branch_event_${widget.event.id}');
      await prefs.remove('pinned_branch_global');
      if (mounted) {
        setState(() {
          _pinnedBranchKey = null;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppStrings.of(ref);
    final isAr = strings.isAr;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 600;

    // Stream live data from Firestore for real-time prize balance updates
    final firestore = ref.watch(firestoreProvider);
    final eventDocStream = widget.event.id.isNotEmpty
        ? firestore.collection('events').doc(widget.event.id).snapshots()
        : null;

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
            maxWidth: 680,
            maxHeight: mediaQuery.size.height * 0.86,
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: eventDocStream,
            builder: (context, snapshot) {
              EventModel liveEvent = widget.event;
              if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                try {
                  liveEvent = EventModel.fromFirestore(snapshot.data!);
                } catch (_) {}
              }

              final allPrizes = liveEvent.allocatedPrizes;

              // Group prizes by branch
              final Map<String, List<AllocatedPrize>> branchPrizesMap = {};
              final Map<String, String> branchDisplayNames = {};

              for (final prize in allPrizes) {
                final key = prize.branchId.isNotEmpty ? prize.branchId : (prize.branchName.isNotEmpty ? prize.branchName : 'general');
                final name = prize.branchName.isNotEmpty ? prize.branchName : (prize.branchId.isNotEmpty ? prize.branchId : strings.allBranchesScope);

                branchPrizesMap.putIfAbsent(key, () => []).add(prize);
                branchDisplayNames[key] = name;
              }

              // Also ensure configured branches from event are included even if zero prizes allocated
              if (liveEvent.branchIds.isNotEmpty) {
                for (int i = 0; i < liveEvent.branchIds.length; i++) {
                  final bId = liveEvent.branchIds[i];
                  final bName = i < liveEvent.branchNames.length ? liveEvent.branchNames[i] : bId;
                  branchPrizesMap.putIfAbsent(bId, () => []);
                  branchDisplayNames.putIfAbsent(bId, () => bName);
                }
              }

              final branchKeys = branchPrizesMap.keys.toList();

              // Fallback / auto-select pinned branch or first branch if no specific branch is selected yet
              if (_selectedBranchKey == null || !branchPrizesMap.containsKey(_selectedBranchKey)) {
                if (_pinnedBranchKey != null && branchPrizesMap.containsKey(_pinnedBranchKey)) {
                  _selectedBranchKey = _pinnedBranchKey;
                } else if (branchKeys.isNotEmpty) {
                  _selectedBranchKey = branchKeys.first;
                }
              }

              final activeBranchPrizes = _selectedBranchKey != null ? (branchPrizesMap[_selectedBranchKey] ?? []) : allPrizes;

              // Total branch stock stats
              int totalAllocatedInBranch = 0;
              int totalRemainingInBranch = 0;
              for (final p in activeBranchPrizes) {
                totalAllocatedInBranch += p.allocatedQuantity;
                totalRemainingInBranch += p.remainingQuantity;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Dialog Header (M3 Title, Company Subtitle & Close Action)
                  _buildHeader(
                    context: context,
                    colorScheme: colorScheme,
                    strings: strings,
                    event: liveEvent,
                    isMobile: isMobile,
                  ),

                  const Divider(height: 1),

                  // 2. Scrollable Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 14 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Branch Selection Dropdown (if campaign has multiple branches)
                          if (branchKeys.length > 1) ...[
                            Text(
                              strings.selectBranchToViewStock,
                              style: GoogleFonts.cairo(
                                fontSize: isMobile ? 12.5 : 13.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildBranchSelector(
                              context: context,
                              colorScheme: colorScheme,
                              strings: strings,
                              branchKeys: branchKeys,
                              branchNames: branchDisplayNames,
                              branchPrizesMap: branchPrizesMap,
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 18),
                          ] else if (branchKeys.length == 1) ...[
                            // Single branch badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.store_rounded,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      branchDisplayNames[branchKeys.first] ?? strings.allBranchesScope,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${activeBranchPrizes.length} ${strings.branchGiftsCountLabel}',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Summary Stat Pill for the selected branch
                          _buildBranchSummaryCard(
                            context: context,
                            colorScheme: colorScheme,
                            strings: strings,
                            remaining: totalRemainingInBranch,
                            total: totalAllocatedInBranch,
                            giftTypesCount: activeBranchPrizes.length,
                            isMobile: isMobile,
                          ),

                          const SizedBox(height: 16),

                          // List of Gifts for the Selected Branch
                          if (activeBranchPrizes.isEmpty)
                            _buildEmptyState(context, colorScheme, strings)
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: activeBranchPrizes.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final prize = activeBranchPrizes[index];
                                return _buildPrizeInventoryCard(
                                  context: context,
                                  colorScheme: colorScheme,
                                  strings: strings,
                                  prize: prize,
                                  isMobile: isMobile,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 1),

                  // 3. Dialog Footer (M3 Close Action)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 20,
                      vertical: isMobile ? 12 : 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(
                              strings.closeInventoryDialog,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 13 : 14,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: isMobile ? 12 : 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
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

  Widget _buildHeader({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required EventModel event,
    required bool isMobile,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 20,
        isMobile ? 14 : 18,
        isMobile ? 8 : 12,
        isMobile ? 12 : 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
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
                  strings.promoterGiftsBalanceTitle,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.eventName} (${event.targetCompany})',
                  style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
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
    );
  }

  Widget _buildBranchSelector({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required List<String> branchKeys,
    required Map<String, String> branchNames,
    required Map<String, List<AllocatedPrize>> branchPrizesMap,
    required bool isMobile,
  }) {
    final effectiveValue = (branchKeys.contains(_selectedBranchKey))
        ? _selectedBranchKey
        : (branchKeys.isNotEmpty ? branchKeys.first : null);

    final isPinned = _pinnedBranchKey != null && _pinnedBranchKey == effectiveValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown Form Field for Branch Selection
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPinned ? colorScheme.primary.withValues(alpha: 0.5) : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isPinned ? 1.5 : 1.0,
            ),
          ),
          child: DropdownButtonFormField<String>(
            key: ValueKey('branch_picker_${effectiveValue}_${branchKeys.length}'),
            initialValue: effectiveValue,
            isExpanded: true,
            dropdownColor: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(Icons.arrow_drop_down_circle_outlined, color: colorScheme.primary, size: 20),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 10 : 12,
              ),
              border: InputBorder.none,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 22),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            ),
            items: branchKeys.map((key) {
              final name = branchNames[key] ?? key;
              final prizes = branchPrizesMap[key] ?? [];
              int remainingInBranch = 0;
              for (final p in prizes) {
                remainingInBranch += p.remainingQuantity;
              }
              final isItemPinned = _pinnedBranchKey == key;

              return DropdownMenuItem<String>(
                value: key,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 13 : 14,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isItemPinned) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 12, color: Colors.amber.shade800),
                            const SizedBox(width: 3),
                            Text(
                              'مثبت',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: remainingInBranch > 0
                            ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                            : colorScheme.errorContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$remainingInBranch متبقي',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: remainingInBranch > 0
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newKey) {
              if (newKey != null) {
                setState(() {
                  _selectedBranchKey = newKey;
                });
                // Automatically save branch to local storage so next time it opens immediately on it
                _savePinnedBranch(newKey);
              }
            },
          ),
        ),

        const SizedBox(height: 8),

        // Pin / Save branch toggle bar
        InkWell(
          onTap: () {
            if (effectiveValue == null) return;
            if (isPinned) {
              _clearPinnedBranch();
            } else {
              _savePinnedBranch(effectiveValue);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Icon(
                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 16,
                  color: isPinned ? Colors.amber.shade800 : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isPinned
                        ? 'تم تثبيت هذا الفرع كافتراضي (يفتح تلقائياً عند فتح النافذة)'
                        : 'انقر لتثبيت هذا الفرع كفرعك الافتراضي الدائم',
                    style: GoogleFonts.cairo(
                      fontSize: 11.5,
                      fontWeight: isPinned ? FontWeight.bold : FontWeight.normal,
                      color: isPinned ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isPinned)
                  Text(
                    'إلغاء التثبيت',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchSummaryCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required int remaining,
    required int total,
    required int giftTypesCount,
    required bool isMobile,
  }) {
    final ratio = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.totalBranchStock,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 12.5 : 13.5,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$remaining',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: remaining > 0 ? colorScheme.primary : colorScheme.error,
                      ),
                    ),
                    TextSpan(
                      text: ' / $total',
                      style: GoogleFonts.cairo(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: remaining == 0
                  ? colorScheme.error
                  : (remaining <= 2 ? Colors.amber.shade700 : colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrizeInventoryCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required AppStrings strings,
    required AllocatedPrize prize,
    required bool isMobile,
  }) {
    final remaining = prize.remainingQuantity;
    final total = prize.allocatedQuantity;
    final ratio = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    final isVoucher = prize.isVoucher;

    final isOut = remaining <= 0;
    final isLow = remaining > 0 && remaining <= 2;

    final Color statusColor = isOut
        ? colorScheme.error
        : (isLow ? Colors.amber.shade800 : Colors.green.shade700);

    final String statusText = isOut
        ? strings.giftStatusEmpty
        : (isLow ? strings.giftStatusLow : strings.giftStatusAvailable);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOut
              ? colorScheme.error.withValues(alpha: 0.3)
              : (isLow ? Colors.amber.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.5)),
          width: isLow || isOut ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.errorContainer.withValues(alpha: 0.5)
                      : (isLow
                          ? Colors.amber.shade100
                          : (isVoucher
                              ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                              : colorScheme.primaryContainer.withValues(alpha: 0.6))),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVoucher ? Icons.confirmation_number_rounded : Icons.card_giftcard_rounded,
                  color: isOut
                      ? colorScheme.error
                      : (isLow ? Colors.amber.shade900 : colorScheme.primary),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prize.name,
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 13.5 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${strings.remainingOutOfTotal} $remaining ${strings.outOfLabel} $total',
                      style: GoogleFonts.cairo(
                        fontSize: isMobile ? 11 : 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.errorContainer
                      : (isLow ? Colors.amber.shade100 : Colors.green.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: GoogleFonts.cairo(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    AppStrings strings,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.card_giftcard_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            strings.noGiftsAllocatedForBranch,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
