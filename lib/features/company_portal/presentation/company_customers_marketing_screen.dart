import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/arabic_numbers_utils.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/slug_utils.dart';
import '../../../core/widgets/switch_point_branding.dart';
import '../../../core/widgets/m3_action_menu.dart';
import '../../../core/widgets/m3_button_groups.dart';
import '../../admin/domain/event_model.dart';
import '../domain/whatsapp_gateway_config_model.dart';
import '../domain/whatsapp_gateway_service.dart';
import '../domain/marketing_contact_model.dart';
import 'widgets/customer_import_dialog.dart';
import 'widgets/whatsapp_campaign_dispatcher_dialog.dart';
import 'widgets/whatsapp_gateway_settings_dialog.dart';
import 'widgets/whatsapp_live_outbox_view.dart';
import 'widgets/whatsapp_screenshot_dialog.dart';

enum MarketingMainTab {
  audience,
  liveOutbox,
}

enum MarketingMessageMode {
  text,
  media,
  poll,
}

enum CustomerSegmentType {
  all,
  activeWhatsApp,
  winners,
  topSpenders,
  repeatShoppers,
}

/// Standalone Dedicated Partner Customer Relationship CRM & WhatsApp Marketing Screen
/// Provides customer intelligence, multi-select targeting, dynamic message templates,
/// sequential WhatsApp dispatching, and contact exporting.
class CompanyCustomersMarketingScreen extends ConsumerStatefulWidget {
  final String? initialEventId;
  final String? lockedCompanySlug;
  final String? lockedCompanyName;
  final bool isEmbedded;

  const CompanyCustomersMarketingScreen({
    super.key,
    this.initialEventId,
    this.lockedCompanySlug,
    this.lockedCompanyName,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<CompanyCustomersMarketingScreen> createState() => _CompanyCustomersMarketingScreenState();
}

class _CompanyCustomersMarketingScreenState extends ConsumerState<CompanyCustomersMarketingScreen> {
  MarketingMainTab _activeMainTab = MarketingMainTab.audience;
  String _selectedCompany = 'all';
  String? _selectedEventId;
  String? _selectedBranch;
  CustomerSegmentType _selectedSegment = CustomerSegmentType.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounceTimer;
  bool _isSearching = false;

  // Pagination state for ultra-fast rendering (Rule 9)
  int _currentPage = 0;
  int _rowsPerPage = 50;

  // Selection state
  final Set<String> _selectedContactIds = {};

  // Marketing message template state
  bool _isComposerExpanded = false;
  late final TextEditingController _messageController;
  MarketingMessageMode _messageMode = MarketingMessageMode.text;
  final TextEditingController _mediaUrlController = TextEditingController();
  final TextEditingController _pollQuestionController = TextEditingController();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(text: 'نعم، أرغب في الاستلام'),
    TextEditingController(text: 'سأزوركم خلال عطلة الأسبوع'),
  ];
  bool _pollMultipleAnswers = false;

  // Verified active WhatsApp numbers cache across sessions
  final Map<String, bool> _verifiedWhatsAppMap = {};

  // Customer purchase transactions indexed by clean phone number (Rule 4 & Transaction Sheet)
  final Map<String, List<Map<String, dynamic>>> _customerTransactionsMap = {};

  // Memoization cache key and cached contact list (Rule 9: O(1) performance)
  String _lastCacheKey = '';
  List<CustomerCampaignContact> _cachedContacts = [];
  double _cachedTotalSpend = 0;
  int _cachedTotalPrizes = 0;
  int _cachedRepeatCount = 0;

  // Filter memoization cache
  String _lastFilterCacheKey = '';
  List<CustomerCampaignContact> _cachedFilteredContacts = [];

  // WhatsApp Gateway Service & Config
  final WhatsAppGatewayService _gatewayService = WhatsAppGatewayService();
  WhatsAppGatewayConfigModel _gatewayConfig = const WhatsAppGatewayConfigModel();

  @override
  void initState() {
    super.initState();
    _selectedEventId = widget.initialEventId;
    _messageController = TextEditingController(
      text: 'أهلاً بك {اسم_العميل}! يسر {الشركة} دعوتك لمهرجان وعروض {الحملة} في فرع {الفرع}. زُرنا اليوم واربح جوائز فورية وقسائم مشتريات قيمة!',
    );
    _loadGatewayConfig();
  }

  Future<void> _loadGatewayConfig() async {
    final config = await _gatewayService.loadConfig(companySlug: widget.lockedCompanySlug);
    if (mounted) {
      setState(() {
        _gatewayConfig = config;
      });
    }
  }

  void _openGatewaySettings(AppStrings strings, bool isAr) {
    showDialog<WhatsAppGatewayConfigModel>(
      context: context,
      builder: (ctx) => WhatsAppGatewaySettingsDialog(
        currentConfig: _gatewayConfig,
        companySlug: widget.lockedCompanySlug,
        strings: strings,
        isAr: isAr,
        onSaved: (updated) {
          setState(() {
            _gatewayConfig = updated;
          });
        },
      ),
    );
  }

  void _openCustomerImportDialog({
    required AppStrings strings,
    required bool isAr,
    required String companySlug,
    required String companyName,
    required List<String> availableBranches,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => CustomerImportDialog(
        companySlug: companySlug,
        companyName: companyName,
        availableBranches: availableBranches,
        strings: strings,
        isAr: isAr,
        onImportSuccess: (savedCount) {
          final cs = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAr
                    ? 'تم حفظ $savedCount عميل بنجاح في قاعدة البيانات!'
                    : '$savedCount customers successfully saved to database!',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              backgroundColor: cs.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _messageController.dispose();
    _mediaUrlController.dispose();
    _pollQuestionController.dispose();
    for (final c in _pollOptionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Debounced search handler: waits 600ms after user stops typing before triggering search
  void _onSearchQueryChanged(String val) {
    _searchDebounceTimer?.cancel();
    if (val.trim() == _searchQuery.trim()) {
      if (mounted && _isSearching) {
        setState(() => _isSearching = false);
      }
      return;
    }
    if (!_isSearching) {
      setState(() => _isSearching = true);
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = val;
        _isSearching = false;
        _currentPage = 0;
      });
    });
  }

  /// Immediate 0ms search execution when pressing Enter or tapping Search icon
  void _executeSearchImmediately([String? val]) {
    _searchDebounceTimer?.cancel();
    final query = val ?? _searchController.text;
    if (!mounted) return;
    setState(() {
      _searchQuery = query;
      _isSearching = false;
      _currentPage = 0;
    });
  }

  /// Immediately resets search query and clears text
  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _currentPage = 0;
    });
  }

  /// Inserts a smart tag into the message composer
  void _insertTag(String tag) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, tag);
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + tag.length),
      );
    } else {
      _messageController.text = '$text $tag';
    }
    setState(() {});
  }

  /// Applies a preset message template
  void _applyPresetTemplate(String template) {
    setState(() {
      _messageController.text = template;
    });
  }

  /// Processes raw transaction documents and stored marketing contacts into unified customer profiles
  void _aggregateCustomers({
    required List<QueryDocumentSnapshot> transactions,
    required List<EventModel> events,
    required String effectiveSlug,
    required String companyName,
    List<MarketingContactModel> customContacts = const [],
  }) {
    final cacheKey = '${transactions.length}_${events.length}_${customContacts.length}_${_selectedCompany}_${_selectedEventId ?? 'all'}_${_selectedBranch ?? 'all'}';
    if (_lastCacheKey == cacheKey) {
      return;
    }

    _customerTransactionsMap.clear();
    final Map<String, CustomerCampaignContact> contactsMap = {};
    int totalPrizes = 0;
    double totalSpend = 0;

    for (final doc in transactions) {
      final data = doc.data() as Map<String, dynamic>? ?? {};

      // Match company slug or target company
      final docCompanySlug = (data['companySlug'] ?? '').toString();
      final docTargetCompany = (data['targetCompany'] ?? '').toString();
      if (effectiveSlug.isNotEmpty) {
        final matchesSlug = docCompanySlug.toLowerCase() == effectiveSlug.toLowerCase() ||
            SlugUtils.toSlug(docTargetCompany).toLowerCase() == effectiveSlug.toLowerCase() ||
            docTargetCompany.trim().toLowerCase() == companyName.trim().toLowerCase();
        if (!matchesSlug) continue;
      }

      // Match campaign if selected
      final campaignId = (data['campaignId'] ?? '').toString();
      if (_selectedEventId != null && _selectedEventId!.isNotEmpty && _selectedEventId != 'all') {
        if (campaignId != _selectedEventId) continue;
      }

      // Customer raw info
      final rawPhone = (data['customerPhone'] ?? data['customer_phone'] ?? data['phone'] ?? '').toString().trim();
      if (rawPhone.isEmpty || rawPhone.length < 6) continue;

      final cleanPhone = WhatsappCampaignDispatcherDialog.formatPhoneForWhatsApp(rawPhone);
      final rawName = (data['customerName'] ?? data['customer_name'] ?? data['name'] ?? '').toString().trim();
      final branch = (data['branch_detected'] ?? data['canonical_branch'] ?? data['branch'] ?? '').toString().trim();

      // Filter branch if selected
      if (_selectedBranch != null && _selectedBranch!.isNotEmpty && _selectedBranch != 'all') {
        if (branch != _selectedBranch) continue;
      }

      // Record transaction into map for fast customer transaction view (Rule 4 & Transaction Sheet)
      _customerTransactionsMap.putIfAbsent(cleanPhone, () => []).add(data);

      // Spend and prizes
      final spend = (data['target_company_total'] ?? data['total_value'] ?? 0);
      final spendVal = spend is num ? spend.toDouble() : 0.0;
      final prizeWon = (data['prize_won'] ?? data['prizeName'] ?? '').toString().trim();
      final List<String> prizes = [];
      if (prizeWon.isNotEmpty && prizeWon != 'null') {
        prizes.add(prizeWon);
        totalPrizes++;
      }

      // Linked gifts / vouchers
      final linkedGifts = data['linkedGifts'] as List?;
      if (linkedGifts != null) {
        for (final lg in linkedGifts) {
          if (lg is Map && lg['giftName'] != null) {
            final gName = lg['giftName'].toString().trim();
            if (gName.isNotEmpty && !prizes.contains(gName)) {
              prizes.add(gName);
              totalPrizes++;
            }
          }
        }
      }

      // Date
      DateTime? visitDate;
      if (data['receipt_date'] is Timestamp) {
        visitDate = (data['receipt_date'] as Timestamp).toDate();
      } else if (data['timestamp'] is Timestamp) {
        visitDate = (data['timestamp'] as Timestamp).toDate();
      } else if (data['receipt_date'] is String) {
        visitDate = DateTime.tryParse(data['receipt_date']);
      }

      if (!contactsMap.containsKey(cleanPhone)) {
        contactsMap[cleanPhone] = CustomerCampaignContact(
          id: cleanPhone,
          name: rawName,
          rawPhone: rawPhone,
          cleanPhone: cleanPhone,
          totalSpend: spendVal,
          totalInvoices: 1,
          prizesWon: prizes,
          branches: branch.isNotEmpty ? [branch] : [],
          lastBranch: branch,
          lastVisitDate: visitDate,
          isWhatsAppActive: _verifiedWhatsAppMap[cleanPhone],
        );
      } else {
        final existing = contactsMap[cleanPhone]!;
        final updatedSpend = existing.totalSpend + spendVal;
        final updatedInvoices = existing.totalInvoices + 1;
        final updatedBranches = List<String>.from(existing.branches);
        if (branch.isNotEmpty && !updatedBranches.contains(branch)) {
          updatedBranches.add(branch);
        }
        final updatedPrizes = List<String>.from(existing.prizesWon);
        for (final p in prizes) {
          if (!updatedPrizes.contains(p)) updatedPrizes.add(p);
        }
        final updatedName = existing.name.isEmpty && rawName.isNotEmpty ? rawName : existing.name;
        final updatedDate = visitDate != null && (existing.lastVisitDate == null || visitDate.isAfter(existing.lastVisitDate!))
            ? visitDate
            : existing.lastVisitDate;

        contactsMap[cleanPhone] = CustomerCampaignContact(
          id: cleanPhone,
          name: updatedName,
          rawPhone: existing.rawPhone,
          cleanPhone: cleanPhone,
          totalSpend: updatedSpend,
          totalInvoices: updatedInvoices,
          prizesWon: updatedPrizes,
          branches: updatedBranches,
          lastBranch: branch.isNotEmpty ? branch : existing.lastBranch,
          lastVisitDate: updatedDate,
          status: existing.status,
          isWhatsAppActive: existing.isWhatsAppActive ?? _verifiedWhatsAppMap[cleanPhone],
        );
      }
      totalSpend += spendVal;
    }

    // Merge custom / Excel-imported marketing contacts
    for (final cc in customContacts) {
      final cleanPhone = cc.cleanPhone;
      if (cleanPhone.isEmpty) continue;

      // Filter branch if selected
      if (_selectedBranch != null && _selectedBranch!.isNotEmpty && _selectedBranch != 'all') {
        if (cc.branch.isNotEmpty && cc.branch != _selectedBranch) continue;
      }

      if (!contactsMap.containsKey(cleanPhone)) {
        final ccc = cc.toCustomerCampaignContact();
        ccc.isWhatsAppActive = _verifiedWhatsAppMap[cleanPhone];
        contactsMap[cleanPhone] = ccc;
      } else {
        // Customer already exists from transactions, enrich name & branch & source
        final existing = contactsMap[cleanPhone]!;
        final updatedBranches = List<String>.from(existing.branches);
        if (cc.branch.isNotEmpty && !updatedBranches.contains(cc.branch)) {
          updatedBranches.add(cc.branch);
        }
        final updatedName = existing.name.isEmpty || existing.name == 'عميل بدون اسم'
            ? cc.name
            : existing.name;

        contactsMap[cleanPhone] = CustomerCampaignContact(
          id: existing.id,
          name: updatedName,
          rawPhone: existing.rawPhone,
          cleanPhone: existing.cleanPhone,
          totalSpend: existing.totalSpend,
          totalInvoices: existing.totalInvoices,
          prizesWon: existing.prizesWon,
          branches: updatedBranches,
          lastBranch: existing.lastBranch.isNotEmpty ? existing.lastBranch : cc.branch,
          lastVisitDate: existing.lastVisitDate ?? cc.createdAt,
          sourceTag: cc.source,
          status: existing.status,
          isWhatsAppActive: existing.isWhatsAppActive ?? _verifiedWhatsAppMap[cleanPhone],
        );
      }
    }

    final allContacts = contactsMap.values.toList();
    allContacts.sort((a, b) {
      // Sort by last visit or total invoices
      if (a.lastVisitDate != null && b.lastVisitDate != null) {
        return b.lastVisitDate!.compareTo(a.lastVisitDate!);
      }
      return b.totalInvoices.compareTo(a.totalInvoices);
    });

    _lastCacheKey = cacheKey;
    _lastFilterCacheKey = ''; // Invalidate filter cache on new dataset
    _cachedContacts = allContacts;
    _cachedTotalSpend = totalSpend;
    _cachedTotalPrizes = totalPrizes;
    _cachedRepeatCount = allContacts.where((c) => c.isRepeat).length;
  }

  /// Filters contacts according to segment and live search query with O(1) memoization
  List<CustomerCampaignContact> _getFilteredContacts() {
    final filterKey = '${_cachedContacts.length}_${_selectedSegment.index}_${_searchQuery.trim()}';
    if (_cachedFilteredContacts.isNotEmpty && _lastFilterCacheKey == filterKey) {
      return _cachedFilteredContacts;
    }

    final result = _cachedContacts.where((contact) {
      // Segment filter
      switch (_selectedSegment) {
        case CustomerSegmentType.all:
          break;
        case CustomerSegmentType.activeWhatsApp:
          if (contact.isWhatsAppActive != true) return false;
          break;
        case CustomerSegmentType.winners:
          if (!contact.isWinner) return false;
          break;
        case CustomerSegmentType.topSpenders:
          if (contact.totalSpend < 200 && contact.totalInvoices < 2) return false;
          break;
        case CustomerSegmentType.repeatShoppers:
          if (!contact.isRepeat) return false;
          break;
      }

      // Search query filter with O(1) pre-computed index (Rule 9)
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim().toEnglishDigits();
        if (!contact.searchIndex.contains(query)) return false;
      }

      return true;
    }).toList();

    _lastFilterCacheKey = filterKey;
    _cachedFilteredContacts = result;
    return result;
  }

  /// Triggers the interactive sequential WhatsApp sender modal
  void _launchWhatsAppCampaign({
    required List<CustomerCampaignContact> targetContacts,
    required String companyName,
    required String campaignName,
    required AppStrings strings,
    required bool isAr,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (targetContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.noCustomersFound),
          backgroundColor: cs.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate Poll if poll mode is active
    if (_messageMode == MarketingMessageMode.poll) {
      final q = _pollQuestionController.text.trim();
      final validOpts = _pollOptionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (q.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.pollQuestionRequired),
            backgroundColor: cs.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (validOpts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.pollRequiresTwoOptions),
            backgroundColor: cs.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Reset dispatch status for all target contacts so fresh launch starts in pending state
    for (final contact in targetContacts) {
      contact.status = ContactDispatchStatus.pending;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WhatsappCampaignDispatcherDialog(
        contacts: targetContacts,
        messageTemplate: _messageController.text,
        companyName: companyName,
        campaignName: campaignName,
        companySlug: widget.lockedCompanySlug,
        strings: strings,
        isAr: isAr,
        attachedMediaUrl: _messageMode == MarketingMessageMode.media ? _mediaUrlController.text.trim() : null,
        pollTitle: _messageMode == MarketingMessageMode.poll ? _pollQuestionController.text.trim() : null,
        pollOptions: _messageMode == MarketingMessageMode.poll
            ? _pollOptionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList()
            : null,
        multiplePollAnswers: _pollMultipleAnswers,
      ),
    );
  }

  /// Feature 4: Filter Active WhatsApp Numbers (فحص وفلترة أرقام الواتساب النشطة)
  Future<void> _checkActiveWhatsAppNumbers({
    required List<CustomerCampaignContact> contactsToCheck,
    required AppStrings strings,
    required bool isAr,
  }) async {
    final cs = Theme.of(context).colorScheme;
    if (contactsToCheck.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.noCustomersFound),
          backgroundColor: cs.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_gatewayConfig.isConfigured) {
      _openGatewaySettings(strings, isAr);
      return;
    }

    bool isCancelled = false;
    int processed = 0;
    int activeCount = 0;
    int inactiveCount = 0;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            final progress = contactsToCheck.isNotEmpty ? processed / contactsToCheck.length : 0.0;

            if (processed == 0 && !isCancelled) {
              Future.microtask(() async {
                for (final contact in contactsToCheck) {
                  if (isCancelled) break;
                  final phone = contact.cleanPhone.isNotEmpty ? contact.cleanPhone : contact.rawPhone;
                  final exists = await _gatewayService.checkNumberExists(
                    config: _gatewayConfig,
                    rawPhone: phone,
                  );
                  if (isCancelled) break;

                  contact.isWhatsAppActive = exists;
                  if (exists != null) {
                    _verifiedWhatsAppMap[contact.cleanPhone] = exists;
                  }
                  processed++;
                  if (exists == true) {
                    activeCount++;
                  } else {
                    inactiveCount++;
                  }

                  if (dialogCtx.mounted) {
                    setDialogState(() {});
                  }
                }

                if (dialogCtx.mounted) {
                  setDialogState(() {});
                }
              });
            }

            final isFinished = processed >= contactsToCheck.length || isCancelled;

            return AlertDialog(
              backgroundColor: cs.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.phonelink_ring_rounded, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAr ? 'فحص أرقام الواتساب النشطة' : 'Filter Active WhatsApp Numbers',
                      style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isAr
                          ? 'جاري فحص قائمة العملاء والتأكد من وجود حساب واتساب مفعل لكل رقم عبر السيرفر الخاص...'
                          : 'Checking customer contact list to verify active WhatsApp accounts via private server...',
                      style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: isFinished && !isCancelled ? 1.0 : progress,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isAr ? 'تم فحص $processed من ${contactsToCheck.length}' : 'Checked $processed of ${contactsToCheck.length}',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$activeCount',
                                      style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                                    ),
                                  ],
                                ),
                                Text(
                                  isAr ? 'حساب نشط' : 'Active WhatsApp',
                                  style: GoogleFonts.cairo(fontSize: 11, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.phonelink_erase_rounded, size: 16, color: cs.error),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$inactiveCount',
                                      style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onErrorContainer),
                                    ),
                                  ],
                                ),
                                Text(
                                  isAr ? 'ليس لديه واتساب' : 'No WhatsApp',
                                  style: GoogleFonts.cairo(fontSize: 11, color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isFinished)
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      Navigator.of(dialogCtx).pop();
                    },
                    child: Text(isAr ? 'إيقاف الفحص' : 'Cancel Check', style: GoogleFonts.cairo(color: cs.error)),
                  )
                else ...[
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                    },
                    child: Text(isAr ? 'إغلاق' : 'Close', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                  if (activeCount > 0)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                      icon: const Icon(Icons.check_box_rounded, size: 18),
                      label: Text(
                        isAr ? 'تحديد الأرقام النشطة فقط ($activeCount)' : 'Select Active Only ($activeCount)',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedContactIds.clear();
                          for (final c in contactsToCheck) {
                            if (c.isWhatsAppActive == true) {
                              _selectedContactIds.add(c.id);
                            }
                          }
                          _selectedSegment = CustomerSegmentType.activeWhatsApp;
                          _lastFilterCacheKey = '';
                        });
                        Navigator.of(dialogCtx).pop();
                      },
                    ),
                ],
              ],
            );
          },
        );
      },
    );

    setState(() {
      _lastFilterCacheKey = '';
    });
  }

  /// Opens dialog to send a test WhatsApp message to any custom mobile number
  void _showCustomNumberTestDialog({
    required BuildContext context,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required String companyName,
    required String campaignName,
  }) {
    final phoneController = TextEditingController();
    final nameController = TextEditingController(text: isAr ? 'عميل تجريبي' : 'Test Customer');
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMobile = MediaQuery.of(context).size.width < 600;
            final testName = nameController.text.trim().isNotEmpty
                ? nameController.text.trim()
                : (isAr ? 'عزيزنا العميل' : 'Valued Customer');

            // Build real-time preview
            String previewText = _messageController.text;
            previewText = previewText.replaceAll('{اسم_العميل}', testName);
            previewText = previewText.replaceAll('{الاسم}', testName);
            previewText = previewText.replaceAll('{customer_name}', testName);
            previewText = previewText.replaceAll('{name}', testName);

            final compName = companyName.trim().isNotEmpty ? companyName.trim() : (isAr ? 'الشركة' : 'Company');
            previewText = previewText.replaceAll('{الشركة}', compName);
            previewText = previewText.replaceAll('{company_name}', compName);
            previewText = previewText.replaceAll('{company}', compName);

            final campName = campaignName.trim().isNotEmpty ? campaignName.trim() : (isAr ? 'المهرجان الترويجي' : 'Promotional Campaign');
            previewText = previewText.replaceAll('{الحملة}', campName);
            previewText = previewText.replaceAll('{campaign_name}', campName);
            previewText = previewText.replaceAll('{campaign}', campName);

            final brName = (_selectedBranch != null && _selectedBranch != 'all')
                ? _selectedBranch!
                : (isAr ? 'الفرع الرئيسي' : 'Main Outlet');
            previewText = previewText.replaceAll('{الفرع}', brName);
            previewText = previewText.replaceAll('{branch_name}', brName);
            previewText = previewText.replaceAll('{branch}', brName);

            final rawInput = phoneController.text.trim().toEnglishDigits();
            final formattedPhone = WhatsappCampaignDispatcherDialog.formatPhoneForWhatsApp(rawInput);
            final isValidPhone = rawInput.replaceAll(RegExp(r'[^0-9]'), '').length >= 8;

            return Dialog(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              cs.primary,
                              cs.primaryContainer,
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
                                color: cs.onPrimary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.science_rounded, color: cs.onPrimary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    strings.sendTestMessage,
                                    style: GoogleFonts.cairo(
                                      fontSize: isMobile ? 15 : 17,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '$companyName • $campaignName',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      color: cs.onPrimary.withValues(alpha: 0.9),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, color: cs.onPrimary),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                            ),
                          ],
                        ),
                      ),

                      // Body
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 14 : 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Notice banner
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        strings.testMessageNotice,
                                        style: GoogleFonts.cairo(fontSize: 12, height: 1.5, color: cs.onSurface),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Mobile number field
                              Text(
                                strings.customerPhoneField,
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: strings.testPhonePlaceholder,
                                  hintStyle: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                                  prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20, color: cs.primary),
                                  suffixIcon: rawInput.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 18),
                                          onPressed: () {
                                            phoneController.clear();
                                            setDialogState(() {});
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: cs.surfaceContainerLow,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  helperText: formattedPhone.isNotEmpty ? 'WhatsApp ID: +$formattedPhone' : null,
                                  helperStyle: GoogleFonts.robotoMono(fontSize: 11, color: cs.primary),
                                ),
                                style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w600),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                              const SizedBox(height: 14),

                              // Customer Name field (optional)
                              Text(
                                strings.testCustomerNameOptional,
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: nameController,
                                decoration: InputDecoration(
                                  hintText: isAr ? 'أدخل اسم للتجربة...' : 'Enter test name...',
                                  hintStyle: GoogleFonts.cairo(fontSize: 12),
                                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                                  filled: true,
                                  fillColor: cs.surfaceContainerLow,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                style: GoogleFonts.cairo(fontSize: 13),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                              const SizedBox(height: 16),

                               // Preview
                              if (_messageMode == MarketingMessageMode.poll) ...[
                                Row(
                                  children: [
                                    Icon(Icons.poll_rounded, size: 16, color: cs.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      strings.pollPreviewTitle,
                                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cs.outlineVariant),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _pollQuestionController.text.trim().isNotEmpty
                                            ? _pollQuestionController.text.trim()
                                            : (isAr ? '(سؤال الاستطلاع)' : '(Poll Question)'),
                                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const Divider(height: 14),
                                      ..._pollOptionControllers
                                          .map((c) => c.text.trim())
                                          .where((s) => s.isNotEmpty)
                                          .map((opt) => Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 2),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.radio_button_unchecked_rounded, size: 14, color: cs.primary),
                                                    const SizedBox(width: 8),
                                                    Expanded(child: Text(opt, style: GoogleFonts.cairo(fontSize: 12))),
                                                  ],
                                                ),
                                              )),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  strings.liveMessagePreview,
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cs.outlineVariant),
                                  ),
                                  child: SelectableText(
                                    previewText,
                                    style: GoogleFonts.cairo(fontSize: 13, height: 1.5, color: cs.onSurface),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),

                              // Active Gateway Status Indicator
                              if (_gatewayConfig.isConfigured)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: cs.outlineVariant),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.cloud_done_rounded, size: 18, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isAr
                                              ? 'البوابة المعتمدة: ${_gatewayConfig.provider.displayName} (إرسال سحابي فوري بالخلفية بدون متصفح)'
                                              : 'Active Gateway: ${_gatewayConfig.provider.displayName} (Instant Background Dispatch without Browser)',
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Launch WhatsApp Test Button
                              SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: isSending
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                        )
                                      : const Icon(Icons.send_rounded, size: 18),
                                  label: Text(
                                    isSending
                                        ? (isAr ? 'جاري الإرسال عبر البوابة...' : 'Sending via Gateway...')
                                        : (_gatewayConfig.isConfigured
                                            ? (isAr ? 'إرسال فوري عبر بوابة ${_gatewayConfig.provider.displayName}' : 'Send via ${_gatewayConfig.provider.displayName}')
                                            : strings.sendTestWhatsApp),
                                    style: GoogleFonts.cairo(fontSize: isMobile ? 13 : 14, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: (!isValidPhone || isSending)
                                      ? null
                                      : () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          if (_gatewayConfig.isConfigured) {
                                            setDialogState(() {
                                              isSending = true;
                                            });
                                            try {
                                              final WhatsAppGatewayResult result;
                                              if (_messageMode == MarketingMessageMode.poll && _pollQuestionController.text.trim().isNotEmpty) {
                                                final opts = _pollOptionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
                                                result = await _gatewayService.sendPollMessage(
                                                  config: _gatewayConfig,
                                                  toPhone: formattedPhone,
                                                  pollTitle: _pollQuestionController.text.trim(),
                                                  pollOptions: opts,
                                                  multipleAnswers: _pollMultipleAnswers,
                                                );
                                              } else if (_messageMode == MarketingMessageMode.media && _mediaUrlController.text.trim().isNotEmpty) {
                                                result = await _gatewayService.sendMediaMessage(
                                                  config: _gatewayConfig,
                                                  toPhone: formattedPhone,
                                                  mediaUrl: _mediaUrlController.text.trim(),
                                                  caption: previewText,
                                                );
                                              } else {
                                                result = await _gatewayService.sendSingleMessage(
                                                  config: _gatewayConfig,
                                                  toPhone: formattedPhone,
                                                  messageText: previewText,
                                                );
                                              }
                                              if (result.isSuccess) {
                                                if (dialogCtx.mounted) {
                                                  Navigator.of(dialogCtx).pop();
                                                }
                                                messenger.showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      isAr
                                                          ? 'تم إرسال رسالة الاختبار بنجاح عبر بوابة ${_gatewayConfig.provider.displayName}! 🚀'
                                                          : 'Test message sent successfully via ${_gatewayConfig.provider.displayName}! 🚀',
                                                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                                    ),
                                                    backgroundColor: cs.primary,
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              } else {
                                                setDialogState(() {
                                                  isSending = false;
                                                });
                                                messenger.showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      result.error ?? (isAr ? 'فشل الإرسال عبر البوابة' : 'Failed to send via Gateway'),
                                                      style: GoogleFonts.cairo(),
                                                    ),
                                                    backgroundColor: cs.error,
                                                    behavior: SnackBarBehavior.floating,
                                                    duration: const Duration(seconds: 5),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              setDialogState(() {
                                                isSending = false;
                                              });
                                              messenger.showSnackBar(
                                                SnackBar(
                                                  content: Text(strings.operationFailed(e.toString())),
                                                  backgroundColor: cs.error,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          } else {
                                            final url = 'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(previewText)}';
                                            final uri = Uri.parse(url);
                                            try {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                              if (dialogCtx.mounted) {
                                                Navigator.of(dialogCtx).pop();
                                              }
                                              messenger.showSnackBar(
                                                SnackBar(
                                                  content: Text(strings.testMessageSentSuccess),
                                                  backgroundColor: cs.primary,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            } catch (e) {
                                              messenger.showSnackBar(
                                                SnackBar(
                                                  content: Text(strings.operationFailed(e.toString())),
                                                  backgroundColor: cs.error,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                ),
                              ),
                              if (_gatewayConfig.isConfigured) ...[
                                const SizedBox(height: 6),
                                Center(
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                    label: Text(
                                      isAr ? 'أو فتح الرسالة في تطبيق/ويب واتساب يدوياً' : 'Or open manually in WhatsApp Web/App',
                                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                                    ),
                                    onPressed: (!isValidPhone || isSending)
                                        ? null
                                        : () async {
                                            final url = 'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(previewText)}';
                                            final uri = Uri.parse(url);
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          },
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),

                              // Secondary Action: Add to Current Audience List
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                label: Text(
                                  strings.addCustomRecipient,
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: isValidPhone
                                    ? () {
                                        final customContact = CustomerCampaignContact(
                                          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                                          name: nameController.text.trim().isNotEmpty ? nameController.text.trim() : (isAr ? 'رقم مخصص' : 'Custom Recipient'),
                                          rawPhone: rawInput,
                                          cleanPhone: formattedPhone,
                                          totalSpend: 0,
                                          totalInvoices: 0,
                                          prizesWon: [],
                                          branches: brName.isNotEmpty ? [brName] : [],
                                          lastBranch: brName,
                                          lastVisitDate: DateTime.now(),
                                        );

                                        setState(() {
                                          _cachedContacts.insert(0, customContact);
                                          _selectedContactIds.add(customContact.id);
                                        });

                                        Navigator.of(dialogCtx).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(isAr ? 'تمت إضافة الرقم إلى قائمة المستلمين وتحديده' : 'Contact added and selected in audience queue'),
                                            backgroundColor: cs.primary,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ],
                          ),
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
    );
  }

  /// Exports filtered or selected customers to an Excel spreadsheet
  Future<void> _exportToExcel(List<CustomerCampaignContact> contacts, String companyName, AppStrings strings) async {
    if (contacts.isEmpty) return;

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    final headers = [
      strings.customerNameField,
      strings.customerPhoneField,
      'WhatsApp Phone',
      strings.totalReceiptsCountCol,
      strings.totalSpendAmountCol,
      strings.prizesWonCol,
      strings.branchesCol,
      strings.lastVisitCol,
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final c in contacts) {
      final dateStr = c.lastVisitDate != null ? intl.DateFormat('yyyy-MM-dd HH:mm').format(c.lastVisitDate!) : 'N/A';
      sheet.appendRow([
        TextCellValue(c.name.isNotEmpty ? c.name : 'N/A'),
        TextCellValue(c.rawPhone),
        TextCellValue('+${c.cleanPhone}'),
        IntCellValue(c.totalInvoices),
        DoubleCellValue(c.totalSpend),
        TextCellValue(c.prizesWon.join(' | ')),
        TextCellValue(c.branches.join(', ')),
        TextCellValue(dateStr),
      ]);
    }

    final fileBytes = excel.encode();
    if (fileBytes != null) {
      final now = DateTime.now();
      final dateStr = '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
      final cleanComp = companyName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '').replaceAll(' ', '_');
      final fileName = 'Tashil_Customers_${cleanComp}_$dateStr.xlsx';

      downloadFileBytes(bytes: fileBytes, fileName: fileName);

      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.onPrimary, size: 20),
                const SizedBox(width: 10),
                Text('${strings.success}: $fileName', style: TextStyle(color: cs.onPrimary)),
              ],
            ),
            backgroundColor: cs.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Exports filtered customers to VCF contact cards for 1-click mobile phonebook import
  void _exportToVcf(List<CustomerCampaignContact> contacts, String companyName, AppStrings strings) {
    if (contacts.isEmpty) return;

    final StringBuffer vcfBuffer = StringBuffer();
    for (final c in contacts) {
      final displayName = c.name.isNotEmpty ? c.name : 'عميل $companyName';
      vcfBuffer.writeln('BEGIN:VCARD');
      vcfBuffer.writeln('VERSION:3.0');
      vcfBuffer.writeln('FN:$displayName ($companyName)');
      vcfBuffer.writeln('TEL;TYPE=CELL,VOICE:+${c.cleanPhone}');
      vcfBuffer.writeln('ORG:$companyName Customer');
      if (c.branches.isNotEmpty) {
        vcfBuffer.writeln('NOTE:Branch: ${c.branches.join(", ")} | Invoices: ${c.totalInvoices}');
      }
      vcfBuffer.writeln('END:VCARD');
    }

    final bytes = utf8.encode(vcfBuffer.toString());
    final now = DateTime.now();
    final dateStr = '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
    final cleanComp = companyName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '').replaceAll(' ', '_');
    final fileName = 'Contacts_${cleanComp}_$dateStr.vcf';

    downloadFileBytes(bytes: bytes, fileName: fileName);

    if (mounted) {
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.contact_phone_rounded, color: cs.onSecondary, size: 20),
              const SizedBox(width: 10),
              Text('${strings.success}: $fileName', style: TextStyle(color: cs.onSecondary)),
            ],
          ),
          backgroundColor: cs.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Displays the full customer transaction history & receipts breakdown sheet (Rule 4 & Transaction Sheet)
  void _showCustomerTransactionsDialog({
    required BuildContext context,
    required CustomerCampaignContact customer,
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required String companyName,
    required String campaignName,
  }) {
    final transactions = _customerTransactionsMap[customer.cleanPhone] ?? [];
    // Sort transactions by date descending (newest first)
    final sortedTransactions = List<Map<String, dynamic>>.from(transactions)
      ..sort((a, b) {
        DateTime? dateA;
        if (a['receipt_date'] is Timestamp) {
          dateA = (a['receipt_date'] as Timestamp).toDate();
        } else if (a['timestamp'] is Timestamp) {
          dateA = (a['timestamp'] as Timestamp).toDate();
        } else if (a['receipt_date'] is String) {
          dateA = DateTime.tryParse(a['receipt_date']);
        }
        DateTime? dateB;
        if (b['receipt_date'] is Timestamp) {
          dateB = (b['receipt_date'] as Timestamp).toDate();
        } else if (b['timestamp'] is Timestamp) {
          dateB = (b['timestamp'] as Timestamp).toDate();
        } else if (b['receipt_date'] is String) {
          dateB = DateTime.tryParse(b['receipt_date']);
        }
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with customer avatar, name, and phone
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          customer.name.isNotEmpty ? customer.name.characters.first : 'ع',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name.isNotEmpty ? customer.name : (isAr ? 'عميل بدون اسم' : 'Unnamed Customer'),
                              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    customer.rawPhone,
                                    style: GoogleFonts.robotoMono(fontSize: 13, color: cs.onSurfaceVariant),
                                  ),
                                  if (customer.isWhatsAppActive != null) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      customer.isWhatsAppActive == true
                                          ? Icons.verified_rounded
                                          : Icons.phonelink_erase_rounded,
                                      size: 16,
                                      color: customer.isWhatsAppActive == true ? cs.primary : cs.error,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                ),

                // Customer Metrics Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: cs.surfaceContainerLowest,
                  child: Row(
                    children: [
                      _buildDialogMetricBadge(
                        icon: Icons.receipt_long_rounded,
                        label: isAr ? 'عدد الفواتير' : 'Invoices',
                        value: '${customer.totalInvoices}',
                        cs: cs,
                      ),
                      const SizedBox(width: 12),
                      _buildDialogMetricBadge(
                        icon: Icons.shopping_bag_rounded,
                        label: isAr ? 'إجمالي المشتريات' : 'Total Spend',
                        value: '${customer.totalSpend.toStringAsFixed(1)} ${isAr ? "ج.م" : "EGP"}',
                        cs: cs,
                      ),
                      const SizedBox(width: 12),
                      _buildDialogMetricBadge(
                        icon: Icons.military_tech_rounded,
                        label: isAr ? 'الجوائز المستلمة' : 'Prizes Won',
                        value: '${customer.prizesWon.length}',
                        cs: cs,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Transactions List
                Expanded(
                  child: sortedTransactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                              const SizedBox(height: 8),
                              Text(
                                isAr ? 'لا توجد فواتير مسجلة في قاعدة البيانات' : 'No recorded transactions found',
                                style: GoogleFonts.cairo(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: sortedTransactions.length,
                          separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final tx = sortedTransactions[i];
                            return _buildTransactionCard(tx, cs, isAr);
                          },
                        ),
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: Text(strings.callCustomerPhone, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final uri = Uri.parse('tel:${customer.rawPhone}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: Text(strings.sendDirectWhatsApp, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          _launchWhatsAppCampaign(
                            targetContacts: [customer],
                            companyName: companyName,
                            campaignName: campaignName,
                            strings: strings,
                            isAr: isAr,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, ColorScheme cs, bool isAr) {
    final receiptNum = (tx['receipt_number'] ?? tx['receiptId'] ?? '').toString();
    final branch = (tx['canonical_branch'] ?? tx['branch_detected'] ?? tx['branch'] ?? tx['store_name'] ?? '').toString();
    final spend = (tx['target_company_total'] ?? tx['total_value'] ?? 0);
    final spendVal = spend is num ? spend.toDouble() : 0.0;
    final prizeWon = (tx['prize_won'] ?? tx['prizeName'] ?? '').toString().trim();

    DateTime? date;
    if (tx['receipt_date'] is Timestamp) {
      date = (tx['receipt_date'] as Timestamp).toDate();
    } else if (tx['timestamp'] is Timestamp) {
      date = (tx['timestamp'] as Timestamp).toDate();
    } else if (tx['receipt_date'] is String) {
      date = DateTime.tryParse(tx['receipt_date']);
    }
    final dateStr = date != null ? intl.DateFormat('yyyy/MM/dd HH:mm').format(date) : '—';
    final items = tx['items'] as List?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receiptNum.isNotEmpty ? '${isAr ? "فاتورة رقم" : "Receipt #"} $receiptNum' : (isAr ? 'فاتورة بدون رقم' : 'Receipt'),
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
                    ),
                    Text(
                      dateStr,
                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${spendVal.toStringAsFixed(1)} ${isAr ? "ج.م" : "EGP"}',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
                ),
              ),
            ],
          ),
          if (branch.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.storefront_rounded, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(branch, style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
          if (prizeWon.isNotEmpty && prizeWon != 'null') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.military_tech_rounded, size: 14, color: cs.onTertiaryContainer),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      prizeWon,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onTertiaryContainer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (items != null && items.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: items.take(5).map((it) {
                final itName = (it is Map ? (it['product_name'] ?? it['name'] ?? it['item'] ?? '') : it).toString();
                final itQty = (it is Map ? (it['quantity'] ?? 1) : 1);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$itQty × $itName',
                    style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDialogMetricBadge({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme cs,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
              ],
            ),
            Text(
              label,
              style: GoogleFonts.cairo(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(ref);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final firestore = ref.watch(firestoreProvider);

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('events').snapshots(),
      builder: (context, eventsSnapshot) {
        final eventsDocs = eventsSnapshot.data?.docs ?? [];
        final allEvents = eventsDocs
            .map((d) {
              try {
                return EventModel.fromFirestore(d);
              } catch (_) {
                return null;
              }
            })
            .whereType<EventModel>()
            .toList();

        // 1. Discover all distinct registered companies across campaigns
        final Set<String> distinctCompaniesSet = {};
        for (final e in allEvents) {
          final comp = e.targetCompany.trim();
          if (comp.isNotEmpty) {
            distinctCompaniesSet.add(comp);
          }
        }
        final distinctCompanies = distinctCompaniesSet.toList()..sort();

        // 2. Resolve active company & events scoping
        final isLockedCompany = widget.lockedCompanySlug != null && widget.lockedCompanySlug!.isNotEmpty;
        final String effectiveSlug;
        final String effectiveCompanyName;
        final List<EventModel> companyEvents;

        if (isLockedCompany) {
          effectiveSlug = widget.lockedCompanySlug!;
          companyEvents = allEvents.where((e) {
            return e.companySlug.toLowerCase() == effectiveSlug.toLowerCase() ||
                SlugUtils.toSlug(e.targetCompany).toLowerCase() == effectiveSlug.toLowerCase();
          }).toList();
          effectiveCompanyName = widget.lockedCompanyName ??
              (companyEvents.isNotEmpty ? companyEvents.first.targetCompany : effectiveSlug);
        } else {
          // Admin Mode: Driven by _selectedCompany dropdown
          if (_selectedCompany != 'all' && distinctCompanies.contains(_selectedCompany)) {
            effectiveCompanyName = _selectedCompany;
            effectiveSlug = SlugUtils.toSlug(_selectedCompany);
            companyEvents = allEvents.where((e) {
              return e.targetCompany.trim().toLowerCase() == _selectedCompany.trim().toLowerCase() ||
                  SlugUtils.toSlug(e.targetCompany).toLowerCase() == effectiveSlug.toLowerCase();
            }).toList();
          } else {
            effectiveCompanyName = isAr ? 'كافة الشركات' : 'All Companies';
            effectiveSlug = '';
            companyEvents = allEvents;
          }
        }

        // All canonical branches across resolved company events
        final Set<String> allBranches = {};
        for (final ev in companyEvents) {
          allBranches.addAll(ev.branchNames);
        }
        final sortedBranches = allBranches.toList()..sort();

        // Query transactions
        Query transactionsQuery = firestore.collection('receipts_transactions');
        if (effectiveSlug.isNotEmpty) {
          transactionsQuery = transactionsQuery.where('companySlug', isEqualTo: effectiveSlug);
        }

        // Query custom & Excel marketing contacts
        Query customContactsQuery = firestore.collection('marketing_contacts');
        if (effectiveSlug.isNotEmpty) {
          customContactsQuery = customContactsQuery.where('companySlug', isEqualTo: effectiveSlug);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: transactionsQuery.snapshots(),
          builder: (context, transSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: customContactsQuery.snapshots(),
              builder: (context, customSnapshot) {
                final transDocs = transSnapshot.data?.docs ?? [];
                final customDocs = customSnapshot.data?.docs ?? [];
                final customContacts = customDocs.map((d) {
                  try {
                    return MarketingContactModel.fromFirestore(d);
                  } catch (_) {
                    return null;
                  }
                }).whereType<MarketingContactModel>().toList();

                // Aggregate customers with memoization
                _aggregateCustomers(
                  transactions: transDocs,
                  events: companyEvents,
                  effectiveSlug: effectiveSlug,
                  companyName: effectiveCompanyName,
                  customContacts: customContacts,
                );

            final filteredContacts = _getFilteredContacts();
            final activeCampaignName = _selectedEventId != null && _selectedEventId != 'all'
                ? (companyEvents.where((e) => e.id == _selectedEventId).map((e) => e.eventName).firstOrNull ?? effectiveCompanyName)
                : effectiveCompanyName;

            return Directionality(
              textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                backgroundColor: cs.surface,
                appBar: widget.isEmbedded
                    ? null
                    : SwitchPointHeader(
                        subtitle: '$effectiveCompanyName • ${strings.customersMarketingNavTitle}',
                      ),
                body: CustomScrollView(
                  slivers: [
                    // 1. Header Banner & Title
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 20, isMobile ? 14 : 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(isMobile ? 10 : 12),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(Icons.forum_rounded, color: cs.onPrimaryContainer, size: isMobile ? 24 : 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isAr ? 'تسويق وتواصل العملاء' : 'Customer Outreach & Marketing',
                                        style: GoogleFonts.cairo(
                                          fontSize: isMobile ? 16 : 22,
                                          fontWeight: FontWeight.bold,
                                          color: cs.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isAr ? 'إدارة قاعدة بيانات المتسوقين وتخصيص حملات الرسائل' : 'Manage shopper audience and direct marketing campaigns',
                                        style: GoogleFonts.cairo(
                                          fontSize: isMobile ? 11 : 13,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isMobile) ...[
                                  const SizedBox(width: 12),
                                  M3ConnectedActionGroup(
                                    height: 40,
                                    borderRadius: 12,
                                    actions: [
                                      M3ConnectedActionItem(
                                        label: isAr ? 'الشاشة' : 'Screen',
                                        icon: Icons.screenshot_monitor_rounded,
                                        isPrimary: true,
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => WhatsAppScreenshotDialog(
                                              config: _gatewayConfig,
                                              strings: strings,
                                              isAr: isAr,
                                            ),
                                          );
                                        },
                                      ),
                                      M3ConnectedActionItem(
                                        label: isAr ? 'إعدادات' : 'Settings',
                                        icon: Icons.tune_rounded,
                                        onPressed: () => _openGatewaySettings(strings, isAr),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            if (isMobile) ...[
                              const SizedBox(height: 10),
                              M3ConnectedActionGroup(
                                height: 38,
                                borderRadius: 10,
                                isExpanded: true,
                                actions: [
                                  M3ConnectedActionItem(
                                    label: isAr ? 'الشاشة' : 'Screen',
                                    icon: Icons.screenshot_monitor_rounded,
                                    isPrimary: true,
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => WhatsAppScreenshotDialog(
                                          config: _gatewayConfig,
                                          strings: strings,
                                          isAr: isAr,
                                        ),
                                      );
                                    },
                                  ),
                                  M3ConnectedActionItem(
                                    label: isAr ? 'إعدادات' : 'Settings',
                                    icon: Icons.tune_rounded,
                                    onPressed: () => _openGatewaySettings(strings, isAr),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),

                            // Main View Switcher (Audience vs Live Outbox)
                            SizedBox(
                              width: double.infinity,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: M3ConnectedButtonGroup<MarketingMainTab>(
                                  height: 42,
                                  borderRadius: 14,
                                  selectedValue: _activeMainTab,
                                  onSelected: (tab) => setState(() => _activeMainTab = tab),
                                  segments: [
                                    M3ButtonSegment<MarketingMainTab>(
                                      value: MarketingMainTab.audience,
                                      label: isAr ? 'دليل العملاء (${_cachedContacts.length})' : 'Audience (${_cachedContacts.length})',
                                      icon: Icons.groups_rounded,
                                    ),
                                    M3ButtonSegment<MarketingMainTab>(
                                      value: MarketingMainTab.liveOutbox,
                                      label: isAr ? 'سجل الإرسال والتسليم' : 'Outbox & Delivery',
                                      icon: Icons.outbox_rounded,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_activeMainTab == MarketingMainTab.audience) ...[
                              const SizedBox(height: 18),

                              // 2. Executive KPI Cards Row
                              RepaintBoundary(
                                child: _buildKpiMetricsGrid(cs, screenWidth, strings, isAr),
                              ),
                              const SizedBox(height: 18),

                              // 3. Campaign & Branch Filter Selectors
                              RepaintBoundary(
                                child: _buildFiltersBar(
                                  cs: cs,
                                  isMobile: isMobile,
                                  isLockedCompany: isLockedCompany,
                                  distinctCompanies: distinctCompanies,
                                  companyEvents: companyEvents,
                                  sortedBranches: sortedBranches,
                                  strings: strings,
                                  isAr: isAr,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 4. Marketing Message Composer Studio (Expandable)
                              RepaintBoundary(
                                child: _buildMarketingStudioCard(
                                  cs: cs,
                                  isMobile: isMobile,
                                  strings: strings,
                                  isAr: isAr,
                                  companyName: effectiveCompanyName,
                                  campaignName: activeCampaignName,
                                  filteredContacts: filteredContacts,
                                ),
                              ),
                              const SizedBox(height: 18),

                              // 5. Customer Segments Tabs & Search Bar & Bulk Actions Toolbar
                              RepaintBoundary(
                                child: _buildAudienceToolbar(
                                  cs: cs,
                                  isMobile: isMobile,
                                  strings: strings,
                                  isAr: isAr,
                                  filteredContacts: filteredContacts,
                                  companyName: effectiveCompanyName,
                                  campaignName: activeCampaignName,
                                  companySlug: effectiveSlug,
                                  availableBranches: sortedBranches,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Content View: Either Live Outbox Log OR Customer Data Table
                    if (_activeMainTab == MarketingMainTab.liveOutbox)
                      SliverToBoxAdapter(
                        child: RepaintBoundary(
                          child: WhatsAppLiveOutboxView(
                            gatewayConfig: _gatewayConfig,
                            companySlug: widget.lockedCompanySlug,
                            strings: strings,
                            isAr: isAr,
                            onOpenSettings: () => _openGatewaySettings(strings, isAr),
                            customerContacts: _cachedContacts,
                          ),
                        ),
                      )
                    else if (filteredContacts.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 32),
                          padding: const EdgeInsets.all(36),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_search_rounded, size: 54, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  strings.noCustomersFound,
                                  style: GoogleFonts.cairo(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (isMobile)
                      _buildMobileCustomerCardsList(filteredContacts, cs, strings, isAr, effectiveCompanyName, activeCampaignName)
                    else
                      _buildDesktopCustomerTable(filteredContacts, cs, strings, isAr, effectiveCompanyName, activeCampaignName),

                    const SliverToBoxAdapter(child: SizedBox(height: 48)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  },
);
}

  /// Builds the 4 executive KPI summary cards with adaptive responsive layouts
  Widget _buildKpiMetricsGrid(ColorScheme cs, double screenWidth, AppStrings strings, bool isAr) {
    final cards = [
      _KpiItem(
        icon: Icons.groups_rounded,
        title: strings.totalCustomersKpi,
        value: '${_cachedContacts.length}',
        accentColor: cs.primary,
      ),
      _KpiItem(
        icon: Icons.shopping_bag_rounded,
        title: strings.totalCustomerSpendKpi,
        value: '${_cachedTotalSpend.toStringAsFixed(1)} ${isAr ? "ج.م" : "EGP"}',
        accentColor: cs.tertiary,
      ),
      _KpiItem(
        icon: Icons.military_tech_rounded,
        title: strings.totalPrizesWonKpi,
        value: '$_cachedTotalPrizes',
        accentColor: cs.secondary,
      ),
      _KpiItem(
        icon: Icons.replay_rounded,
        title: strings.repeatShoppersKpi,
        value: '$_cachedRepeatCount',
        accentColor: cs.primary,
      ),
    ];

    if (screenWidth < 600) {
      // Small to standard smartphones (360px - 599px)
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: cards.map((c) => _buildSingleKpiCard(c, cs, isCompact: true)).toList(),
      );
    } else if (screenWidth < 1100) {
      // Tablets / Medium screens
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.8,
        children: cards.map((c) => _buildSingleKpiCard(c, cs, isCompact: false)).toList(),
      );
    }

    // Large desktop displays
    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildSingleKpiCard(c, cs, isCompact: false),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildSingleKpiCard(_KpiItem item, ColorScheme cs, {bool isCompact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isCompact ? 8 : 10),
            decoration: BoxDecoration(
              color: item.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.accentColor, size: isCompact ? 20 : 24),
          ),
          SizedBox(width: isCompact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.cairo(
                    fontSize: isCompact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    item.value,
                    style: GoogleFonts.cairo(
                      fontSize: isCompact ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Filters dropdown toolbar (Campaign & Branch)
  /// Filters dropdown toolbar (Company, Campaign & Branch)
  Widget _buildFiltersBar({
    required ColorScheme cs,
    required bool isMobile,
    required bool isLockedCompany,
    required List<String> distinctCompanies,
    required List<EventModel> companyEvents,
    required List<String> sortedBranches,
    required AppStrings strings,
    required bool isAr,
  }) {
    // 1. Deduplicate company events by ID to prevent any duplicate dropdown values
    final Map<String, EventModel> uniqueEventsMap = {};
    for (final e in companyEvents) {
      if (e.id.isNotEmpty) {
        uniqueEventsMap[e.id] = e;
      }
    }
    final uniqueEvents = uniqueEventsMap.values.toList();

    // 3. Deduplicate branches
    final uniqueBranches = sortedBranches.where((b) => b.trim().isNotEmpty).toSet().toList();

    final hasActiveFilter = (!isLockedCompany && _selectedCompany != 'all') ||
        (_selectedEventId != null && _selectedEventId != 'all') ||
        (_selectedBranch != null && _selectedBranch != 'all');

    final companyMenu = M3ActionMenu(
      tooltip: isAr ? 'تصفية حسب الشركة' : 'Filter by Company',
      minWidth: 220,
      maxWidth: 320,
      maxHeight: 400,
      anchorBuilder: (context, controller, child) {
        final isFiltered = _selectedCompany != 'all';
        final label = isFiltered ? _selectedCompany : (isAr ? 'كافة الشركات' : 'All Companies');
        return InkWell(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isFiltered ? cs.primaryContainer : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isFiltered ? cs.primary : cs.outlineVariant),
            ),
            child: Row(
              mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.business_rounded,
                  size: 18,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                      color: isFiltered ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
      children: [
        M3ActionMenu.header(context: context, title: isAr ? 'اختيار الشركة' : 'Select Company'),
        M3ActionMenu.item(
          context: context,
          label: isAr ? 'كافة الشركات' : 'All Companies',
          icon: Icons.business_rounded,
          isSelected: _selectedCompany == 'all',
          onPressed: () {
            setState(() {
              _selectedCompany = 'all';
              _selectedEventId = 'all';
              _selectedBranch = 'all';
              _currentPage = 0;
            });
          },
        ),
        if (distinctCompanies.isNotEmpty) M3ActionMenu.divider(),
        ...distinctCompanies.map((c) => M3ActionMenu.item(
          context: context,
          label: c,
          isSelected: _selectedCompany == c,
          onPressed: () {
            setState(() {
              _selectedCompany = c;
              _selectedEventId = 'all';
              _selectedBranch = 'all';
              _currentPage = 0;
            });
          },
        )),
      ],
    );

    final campaignMenu = M3ActionMenu(
      tooltip: strings.eventsTitle,
      minWidth: 240,
      maxWidth: 340,
      maxHeight: 400,
      anchorBuilder: (context, controller, child) {
        final isFiltered = _selectedEventId != null && _selectedEventId != 'all';
        final selectedEvent = uniqueEvents.where((e) => e.id == _selectedEventId).firstOrNull;
        final label = isFiltered && selectedEvent != null ? selectedEvent.eventName : (isAr ? 'كافة الحملات' : 'All Campaigns');
        return InkWell(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isFiltered ? cs.primaryContainer : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isFiltered ? cs.primary : cs.outlineVariant),
            ),
            child: Row(
              mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.campaign_rounded,
                  size: 18,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                      color: isFiltered ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
      children: [
        M3ActionMenu.header(context: context, title: isAr ? 'اختيار الحملة' : 'Select Campaign'),
        M3ActionMenu.item(
          context: context,
          label: isAr ? 'كافة الحملات' : 'All Campaigns',
          icon: Icons.campaign_rounded,
          isSelected: _selectedEventId == null || _selectedEventId == 'all',
          onPressed: () {
            setState(() {
              _selectedEventId = 'all';
              _currentPage = 0;
            });
          },
        ),
        if (uniqueEvents.isNotEmpty) M3ActionMenu.divider(),
        ...uniqueEvents.map((e) => M3ActionMenu.item(
          context: context,
          label: e.eventName,
          isSelected: _selectedEventId == e.id,
          onPressed: () {
            setState(() {
              _selectedEventId = e.id;
              _currentPage = 0;
            });
          },
        )),
      ],
    );

    final branchMenu = M3ActionMenu(
      tooltip: strings.branchField,
      minWidth: 220,
      maxWidth: 320,
      maxHeight: 400,
      anchorBuilder: (context, controller, child) {
        final isFiltered = _selectedBranch != null && _selectedBranch != 'all';
        final label = isFiltered ? _selectedBranch! : (isAr ? 'كافة الفروع' : 'All Branches');
        return InkWell(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isFiltered ? cs.primaryContainer : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isFiltered ? cs.primary : cs.outlineVariant),
            ),
            child: Row(
              mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                      color: isFiltered ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: isFiltered ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
      children: [
        M3ActionMenu.header(context: context, title: isAr ? 'اختيار الفرع' : 'Select Branch'),
        M3ActionMenu.item(
          context: context,
          label: isAr ? 'كافة الفروع' : 'All Branches',
          icon: Icons.storefront_rounded,
          isSelected: _selectedBranch == null || _selectedBranch == 'all',
          onPressed: () {
            setState(() {
              _selectedBranch = 'all';
              _currentPage = 0;
            });
          },
        ),
        if (uniqueBranches.isNotEmpty) M3ActionMenu.divider(),
        ...uniqueBranches.map((b) => M3ActionMenu.item(
          context: context,
          label: b,
          isSelected: _selectedBranch == b,
          onPressed: () {
            setState(() {
              _selectedBranch = b;
              _currentPage = 0;
            });
          },
        )),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isLockedCompany) ...[
                  companyMenu,
                  const SizedBox(height: 10),
                ],
                campaignMenu,
                const SizedBox(height: 10),
                branchMenu,
                if (hasActiveFilter) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                    label: Text(
                      isAr ? 'إعادة ضبط كافة الفلاتر' : 'Reset All Filters',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedCompany = 'all';
                        _selectedEventId = 'all';
                        _selectedBranch = 'all';
                        _currentPage = 0;
                      });
                    },
                  ),
                ],
              ],
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isLockedCompany)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: companyMenu,
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: campaignMenu,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: branchMenu,
                ),
                if (hasActiveFilter)
                  Tooltip(
                    message: isAr ? 'إعادة ضبط كافة الفلاتر' : 'Reset All Filters',
                    child: IconButton.filledTonal(
                      style: IconButton.styleFrom(
                        backgroundColor: cs.errorContainer.withValues(alpha: 0.5),
                        foregroundColor: cs.error,
                      ),
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      onPressed: () {
                        setState(() {
                          _selectedCompany = 'all';
                          _selectedEventId = 'all';
                          _selectedBranch = 'all';
                          _currentPage = 0;
                        });
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  /// Promotional Message Composer & Studio
  Widget _buildMarketingStudioCard({
    required ColorScheme cs,
    required bool isMobile,
    required AppStrings strings,
    required bool isAr,
    required String companyName,
    required String campaignName,
    required List<CustomerCampaignContact> filteredContacts,
  }) {
    final targetContacts = _selectedContactIds.isNotEmpty
        ? filteredContacts.where((c) => _selectedContactIds.contains(c.id)).toList()
        : filteredContacts;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar of the Studio
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _isComposerExpanded = !_isComposerExpanded),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 12 : 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.forum_rounded, color: cs.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.composeWhatsAppCampaign,
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isAr
                              ? 'صياغة العرض وإرسال تتابعي للعملاء'
                              : 'Personalize campaign message & dispatch queue',
                          style: GoogleFonts.cairo(
                            fontSize: isMobile ? 11 : 12,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quick Launch Queue Button directly from header
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      isMobile
                          ? '(${targetContacts.length})'
                          : '${isAr ? "إرسال الحملة" : "Send Campaign"} (${targetContacts.length})',
                      style: GoogleFonts.cairo(fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _launchWhatsAppCampaign(
                      targetContacts: targetContacts,
                      companyName: companyName,
                      campaignName: campaignName,
                      strings: strings,
                      isAr: isAr,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isComposerExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Studio Content
          if (_isComposerExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Message Mode Selector (M3ConnectedButtonGroup)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: M3ConnectedButtonGroup<MarketingMessageMode>(
                      selectedValue: _messageMode,
                      onSelected: (mode) => setState(() => _messageMode = mode),
                      segments: [
                        M3ButtonSegment(
                          value: MarketingMessageMode.text,
                          label: isAr ? 'رسالة نصية' : 'Text',
                          icon: Icons.article_rounded,
                        ),
                        M3ButtonSegment(
                          value: MarketingMessageMode.media,
                          label: isAr ? 'بوستر مصور' : 'Media',
                          icon: Icons.image_rounded,
                        ),
                        M3ButtonSegment(
                          value: MarketingMessageMode.poll,
                          label: isAr ? 'استطلاع رأي' : 'Poll',
                          icon: Icons.poll_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Feature 1: Media Poster & Image Attachment
                  if (_messageMode == MarketingMessageMode.media) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.photo_library_rounded, size: 18, color: cs.primary),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? 'رابط بوستر العرض' : 'Media Poster URL',
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _mediaUrlController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'https://example.com/promotions/supermarket_offer.jpg',
                              hintStyle: GoogleFonts.cairo(fontSize: 12),
                              prefixIcon: const Icon(Icons.link_rounded, size: 20),
                              suffixIcon: _mediaUrlController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () => setState(() => _mediaUrlController.clear()),
                                    )
                                  : null,
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            style: GoogleFonts.robotoMono(fontSize: 12),
                          ),
                          if (_mediaUrlController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 180),
                                width: double.infinity,
                                color: cs.surfaceContainerHighest,
                                child: Image.network(
                                  _mediaUrlController.text.trim(),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image_rounded, size: 16, color: cs.error),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              isAr ? 'تعذر تحميل المعاينة، يرجى التأكد من صحة الرابط' : 'Unable to preview image from URL',
                                              style: GoogleFonts.cairo(fontSize: 12, color: cs.error),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            isAr
                                ? 'يتم إرسال الصورة بجانب نص الرسالة كحزمة وسائط متكاملة'
                                : 'The image will be dispatched together with the caption text',
                            style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Feature 2: Interactive WhatsApp Polls
                  if (_messageMode == MarketingMessageMode.poll) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.poll_rounded, size: 18, color: cs.primary),
                              const SizedBox(width: 8),
                              Text(
                                isAr ? 'استطلاع رأي تفاعلي' : 'Interactive WhatsApp Poll',
                                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pollQuestionController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: isAr ? 'سؤال الاستطلاع' : 'Poll Question',
                              hintText: isAr ? 'مثال: ما رأيك في هدايا العرض؟' : 'e.g. Which branch do you prefer?',
                              prefixIcon: const Icon(Icons.help_outline_rounded, size: 20),
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isAr ? 'خيارات التصويت المتاحة:' : 'Poll Choices for Customer:',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(_pollOptionControllers.length, (optIdx) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: cs.primaryContainer,
                                    child: Text(
                                      '${optIdx + 1}',
                                      style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _pollOptionControllers[optIdx],
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        hintText: isAr ? 'الخيار رقم ${optIdx + 1}' : 'Option ${optIdx + 1}',
                                        filled: true,
                                        fillColor: cs.surfaceContainerLow,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      style: GoogleFonts.cairo(fontSize: 12),
                                    ),
                                  ),
                                  if (_pollOptionControllers.length > 2)
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: cs.error),
                                      onPressed: () {
                                        setState(() {
                                          _pollOptionControllers.removeAt(optIdx).dispose();
                                        });
                                      },
                                    ),
                                ],
                              ),
                            );
                          }),
                          if (_pollOptionControllers.length < 12)
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(isAr ? 'إضافة خيار تصويت' : 'Add Poll Option', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                              onPressed: () {
                                setState(() {
                                  _pollOptionControllers.add(TextEditingController());
                                });
                              },
                            ),
                          const Divider(height: 1),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              isAr ? 'السماح باختيارات متعددة في التصويت' : 'Allow multiple poll answers',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            value: _pollMultipleAnswers,
                            activeThumbColor: cs.primary,
                            onChanged: (val) => setState(() => _pollMultipleAnswers = val),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Preset template pills (shown in text mode)
                  if (_messageMode != MarketingMessageMode.poll) ...[
                    Text(
                      _messageMode == MarketingMessageMode.media
                          ? (isAr ? 'صياغة البوستر الترويجي (Caption):' : 'Promotional Caption:')
                          : strings.presetTemplatesTitle,
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: Icon(Icons.campaign_rounded, size: 16, color: cs.primary),
                          label: Text(strings.templateNewEvent, style: GoogleFonts.cairo(fontSize: 12)),
                          onPressed: () => _applyPresetTemplate(
                            'أهلاً بك {اسم_العميل}! يسر {الشركة} دعوتك لمهرجان وعروض {الحملة} في فرع {الفرع}. زُرنا اليوم واربح جوائز فورية وقسائم مشتريات قيمة!',
                          ),
                        ),
                        ActionChip(
                          avatar: Icon(Icons.card_giftcard_rounded, size: 16, color: cs.tertiary),
                          label: Text(strings.templateRewardVoucher, style: GoogleFonts.cairo(fontSize: 12)),
                          onPressed: () => _applyPresetTemplate(
                            'مرحباً {اسم_العميل}، شكراً لتسوقك الدائم لمنتجات {الشركة}. يسعدنا إهداؤك فرصة حصرية في مهرجاننا الجديد {الحملة} بفرع {الفرع}. ننتظرك لتستلم هديتك!',
                          ),
                        ),
                        ActionChip(
                          avatar: Icon(Icons.local_fire_department_rounded, size: 16, color: cs.secondary),
                          label: Text(strings.templateWeekendOffer, style: GoogleFonts.cairo(fontSize: 12)),
                          onPressed: () => _applyPresetTemplate(
                            'عروض حصرية من {الشركة} لنهاية الأسبوع بفرع {الفرع}! خصومات استثنائية وجوائز فورية بانتظارك في {الحملة}. لا تفوّت الفرصة!',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Message Editor TextField
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: strings.messageTemplatePlaceholder,
                      hintStyle: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: cs.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    style: GoogleFonts.cairo(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 12),

                  // Smart Placeholder Buttons
                  isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.insertVariable,
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _buildTagChip('{اسم_العميل}', cs),
                                _buildTagChip('{الشركة}', cs),
                                _buildTagChip('{الحملة}', cs),
                                _buildTagChip('{الفرع}', cs),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Text(
                              strings.insertVariable,
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildTagChip('{اسم_العميل}', cs),
                                  _buildTagChip('{الشركة}', cs),
                                  _buildTagChip('{الحملة}', cs),
                                  _buildTagChip('{الفرع}', cs),
                                ],
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 16),

                  // Dedicated Test Send Banner & Action
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.science_rounded, size: 20, color: cs.secondary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      strings.sendTestMessage,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                strings.testMessageNotice,
                                style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant, height: 1.4),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.primaryContainer,
                                  foregroundColor: cs.onPrimaryContainer,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(Icons.send_to_mobile_rounded, size: 18, color: cs.primary),
                                label: Text(
                                  isAr ? 'تجربة إرسال' : strings.quickTestSend,
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _showCustomNumberTestDialog(
                                  context: context,
                                  cs: cs,
                                  strings: strings,
                                  isAr: isAr,
                                  companyName: companyName,
                                  campaignName: campaignName,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.science_rounded, size: 20, color: cs.secondary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.sendTestMessage,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    Text(
                                      strings.testMessageNotice,
                                      style: GoogleFonts.cairo(fontSize: 11, color: cs.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.primaryContainer,
                                  foregroundColor: cs.onPrimaryContainer,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(Icons.send_to_mobile_rounded, size: 18, color: cs.primary),
                                label: Text(
                                  isAr ? 'تجربة إرسال' : strings.quickTestSend,
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _showCustomNumberTestDialog(
                                  context: context,
                                  cs: cs,
                                  strings: strings,
                                  isAr: isAr,
                                  companyName: companyName,
                                  campaignName: campaignName,
                                ),
                              ),
                            ],
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

  Widget _buildTagChip(String tag, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _insertTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          tag,
          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
        ),
      ),
    );
  }

  /// Audience Segments & Actions Toolbar (Select All, Export, Search)
  Widget _buildAudienceToolbar({
    required ColorScheme cs,
    required bool isMobile,
    required AppStrings strings,
    required bool isAr,
    required List<CustomerCampaignContact> filteredContacts,
    required String companyName,
    required String campaignName,
    required String companySlug,
    required List<String> availableBranches,
  }) {
    final allFilteredSelected = filteredContacts.isNotEmpty &&
        filteredContacts.every((c) => _selectedContactIds.contains(c.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Segments Button Group
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: M3ConnectedButtonGroup<CustomerSegmentType>(
            selectedValue: _selectedSegment,
            onSelected: (seg) => setState(() => _selectedSegment = seg),
            segments: [
              M3ButtonSegment(
                value: CustomerSegmentType.all,
                label: isAr ? 'كافة العملاء' : 'All',
                icon: Icons.people_rounded,
              ),
              M3ButtonSegment(
                value: CustomerSegmentType.winners,
                label: isAr ? 'الفائزون' : 'Winners',
                icon: Icons.emoji_events_rounded,
              ),
              M3ButtonSegment(
                value: CustomerSegmentType.topSpenders,
                label: isAr ? 'الأعلى إنفاقاً' : 'Top Spenders',
                icon: Icons.star_rounded,
              ),
              M3ButtonSegment(
                value: CustomerSegmentType.repeatShoppers,
                label: isAr ? 'المتكررون' : 'Repeat',
                icon: Icons.replay_rounded,
              ),
              M3ButtonSegment(
                value: CustomerSegmentType.activeWhatsApp,
                label: isAr
                    ? 'واتساب نشط (${_verifiedWhatsAppMap.values.where((v) => v).length})'
                    : 'WhatsApp (${_verifiedWhatsAppMap.values.where((v) => v).length})',
                icon: Icons.verified_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Search Bar and Action Buttons
        isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search field full-width
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchQueryChanged,
                    onSubmitted: (val) => _executeSearchImmediately(val),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: strings.searchCustomerPlaceholder,
                      hintStyle: GoogleFonts.cairo(fontSize: 13),
                      prefixIcon: IconButton(
                        icon: _isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search_rounded, size: 20),
                        tooltip: 'بحث فوري',
                        onPressed: () => _executeSearchImmediately(),
                      ),
                      suffixIcon: (_searchQuery.isNotEmpty || _searchController.text.isNotEmpty)
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: _clearSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Actions row on mobile
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Add / Import Customers Button (Mobile)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: Text(
                          isAr ? 'إضافة عملاء' : 'Add Customers',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openCustomerImportDialog(
                          strings: strings,
                          isAr: isAr,
                          companySlug: companySlug,
                          companyName: companyName,
                          availableBranches: availableBranches,
                        ),
                      ),

                      // Filter Active WhatsApp Numbers (Mobile)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.secondaryContainer,
                          foregroundColor: cs.onSecondaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.phonelink_ring_rounded, size: 16),
                        label: Text(
                          isAr ? 'فحص الواتساب' : 'Check WhatsApp',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: filteredContacts.isEmpty
                            ? null
                            : () => _checkActiveWhatsAppNumbers(
                                  contactsToCheck: filteredContacts,
                                  strings: strings,
                                  isAr: isAr,
                                ),
                      ),

                      // Select All / Deselect button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(
                          allFilteredSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color: allFilteredSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        label: Text(
                          allFilteredSelected
                              ? (isAr ? 'إلغاء التحديد' : 'Deselect')
                              : (isAr ? 'تحديد الكل' : 'Select All'),
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setState(() {
                            if (allFilteredSelected) {
                              for (final c in filteredContacts) {
                                _selectedContactIds.remove(c.id);
                              }
                            } else {
                              for (final c in filteredContacts) {
                                _selectedContactIds.add(c.id);
                              }
                            }
                          });
                        },
                      ),

                      // Selected Counter Chip
                      if (_selectedContactIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            strings.selectedCustomersCount(_selectedContactIds.length),
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),

                      // Export to Excel
                      Tooltip(
                        message: strings.exportContactsExcel,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.table_view_rounded, size: 18),
                          onPressed: () => _exportToExcel(
                            _selectedContactIds.isNotEmpty
                                ? filteredContacts.where((c) => _selectedContactIds.contains(c.id)).toList()
                                : filteredContacts,
                            companyName,
                            strings,
                          ),
                        ),
                      ),

                      // Export VCF Contact Cards
                      Tooltip(
                        message: strings.exportVcfContacts,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.contact_phone_rounded, size: 18),
                          onPressed: () => _exportToVcf(
                            _selectedContactIds.isNotEmpty
                                ? filteredContacts.where((c) => _selectedContactIds.contains(c.id)).toList()
                                : filteredContacts,
                            companyName,
                            strings,
                          ),
                        ),
                      ),

                      // Quick Test Send to custom number
                      Tooltip(
                        message: strings.sendTestMessage,
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: cs.tertiaryContainer,
                            foregroundColor: cs.onTertiaryContainer,
                          ),
                          icon: const Icon(Icons.science_rounded, size: 18),
                          onPressed: () => _showCustomNumberTestDialog(
                            context: context,
                            cs: cs,
                            strings: strings,
                            isAr: isAr,
                            companyName: companyName,
                            campaignName: campaignName,
                          ),
                        ),
                      ),

                      // WhatsApp Gateway Settings Shortcut
                      Tooltip(
                        message: strings.whatsappGatewayTitle,
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: _gatewayConfig.isConfigured
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            foregroundColor: _gatewayConfig.isConfigured
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                          onPressed: () => _openGatewaySettings(strings, isAr),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Search field
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchQueryChanged,
                      onSubmitted: (val) => _executeSearchImmediately(val),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: strings.searchCustomerPlaceholder,
                        hintStyle: GoogleFonts.cairo(fontSize: 13),
                        prefixIcon: IconButton(
                          icon: _isSearching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search_rounded, size: 20),
                          tooltip: 'بحث فوري',
                          onPressed: () => _executeSearchImmediately(),
                        ),
                        suffixIcon: (_searchQuery.isNotEmpty || _searchController.text.isNotEmpty)
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: _clearSearch,
                              )
                            : null,
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                  // Select All & Actions Group
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Add / Import Customers Button (Desktop)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(
                          isAr ? 'إضافة عملاء' : 'Add Customers',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openCustomerImportDialog(
                          strings: strings,
                          isAr: isAr,
                          companySlug: companySlug,
                          companyName: companyName,
                          availableBranches: availableBranches,
                        ),
                      ),

                      // Filter Active WhatsApp Numbers (Desktop)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.secondaryContainer,
                          foregroundColor: cs.onSecondaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.phonelink_ring_rounded, size: 18),
                        label: Text(
                          isAr ? 'فحص الواتساب' : 'Check Active WhatsApp',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: filteredContacts.isEmpty
                            ? null
                            : () => _checkActiveWhatsAppNumbers(
                                  contactsToCheck: filteredContacts,
                                  strings: strings,
                                  isAr: isAr,
                                ),
                      ),

                      // Select All / Deselect button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(
                          allFilteredSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color: allFilteredSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        label: Text(
                          allFilteredSelected
                              ? (isAr ? 'إلغاء التحديد' : 'Deselect')
                              : (isAr ? 'تحديد الكل' : 'Select All'),
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setState(() {
                            if (allFilteredSelected) {
                              for (final c in filteredContacts) {
                                _selectedContactIds.remove(c.id);
                              }
                            } else {
                              for (final c in filteredContacts) {
                                _selectedContactIds.add(c.id);
                              }
                            }
                          });
                        },
                      ),

                      // Selected Counter Chip
                      if (_selectedContactIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            strings.selectedCustomersCount(_selectedContactIds.length),
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),

                      // Export to Excel
                      Tooltip(
                        message: strings.exportContactsExcel,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.table_view_rounded, size: 20),
                          onPressed: () => _exportToExcel(
                            _selectedContactIds.isNotEmpty
                                ? filteredContacts.where((c) => _selectedContactIds.contains(c.id)).toList()
                                : filteredContacts,
                            companyName,
                            strings,
                          ),
                        ),
                      ),

                      // Export VCF Contact Cards
                      Tooltip(
                        message: strings.exportVcfContacts,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.contact_phone_rounded, size: 20),
                          onPressed: () => _exportToVcf(
                            _selectedContactIds.isNotEmpty
                                ? filteredContacts.where((c) => _selectedContactIds.contains(c.id)).toList()
                                : filteredContacts,
                            companyName,
                            strings,
                          ),
                        ),
                      ),

                      // Quick Test Send to custom number
                      Tooltip(
                        message: strings.sendTestMessage,
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: cs.tertiaryContainer,
                            foregroundColor: cs.onTertiaryContainer,
                          ),
                          icon: const Icon(Icons.science_rounded, size: 20),
                          onPressed: () => _showCustomNumberTestDialog(
                            context: context,
                            cs: cs,
                            strings: strings,
                            isAr: isAr,
                            companyName: companyName,
                            campaignName: campaignName,
                          ),
                        ),
                      ),

                      // WhatsApp Gateway Settings Shortcut
                      Tooltip(
                        message: strings.whatsappGatewayTitle,
                        child: IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: _gatewayConfig.isConfigured
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            foregroundColor: _gatewayConfig.isConfigured
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          icon: const Icon(Icons.cloud_sync_rounded, size: 20),
                          onPressed: () => _openGatewaySettings(strings, isAr),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ],
    );
  }

  /// Desktop Customers Table with dynamic width stretching and ultra-fast 60 FPS pagination
  Widget _buildDesktopCustomerTable(
    List<CustomerCampaignContact> contacts,
    ColorScheme cs,
    AppStrings strings,
    bool isAr,
    String companyName,
    String campaignName,
  ) {
    final totalContacts = contacts.length;
    final totalPages = _rowsPerPage > 0 ? (totalContacts / _rowsPerPage).ceil() : 1;
    final safeCurrentPage = _currentPage < 0 ? 0 : (_currentPage >= totalPages ? (totalPages > 0 ? totalPages - 1 : 0) : _currentPage);
    final startIndex = totalContacts == 0 ? 0 : safeCurrentPage * _rowsPerPage;
    final int endIndex = (startIndex + _rowsPerPage > totalContacts) ? totalContacts : (startIndex + _rowsPerPage);
    final pagedContacts = totalContacts == 0 ? <CustomerCampaignContact>[] : contacts.sublist(startIndex, endIndex);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final minTableWidth = math.max(availableWidth, 1100.0);

            return RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minTableWidth),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHighest.withValues(alpha: 0.5)),
                          horizontalMargin: 20,
                          columnSpacing: 24,
                          columns: [
                            const DataColumn(label: SizedBox(width: 24)),
                            DataColumn(label: Text(strings.customerNameField, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.customerPhoneField, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.totalReceiptsCountCol, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.totalSpendAmountCol, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.prizesWonCol, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.branchesCol, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.lastVisitCol, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(strings.actions, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                          ],
                          rows: pagedContacts.map((c) {
                            final isSelected = _selectedContactIds.contains(c.id);
                            final dateStr = c.lastVisitDate != null ? intl.DateFormat('yyyy/MM/dd').format(c.lastVisitDate!) : '—';

                            return DataRow(
                              selected: isSelected,
                              onSelectChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedContactIds.add(c.id);
                                  } else {
                                    _selectedContactIds.remove(c.id);
                                  }
                                });
                              },
                              cells: [
                                // Checkbox
                                DataCell(
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: cs.primary,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedContactIds.add(c.id);
                                        } else {
                                          _selectedContactIds.remove(c.id);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                // Customer Avatar + Name (Clickable to view transactions)
                                DataCell(
                                  Tooltip(
                                    message: isAr ? 'عرض سجل فواتير ومعاملات العميل' : 'View customer transactions & receipts',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showCustomerTransactionsDialog(
                                        context: context,
                                        customer: c,
                                        cs: cs,
                                        strings: strings,
                                        isAr: isAr,
                                        companyName: companyName,
                                        campaignName: campaignName,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 220),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: cs.primary.withValues(alpha: 0.15),
                                              child: Text(
                                                c.name.isNotEmpty ? c.name.characters.first : 'ع',
                                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    c.name.isNotEmpty ? c.name : (isAr ? 'عميل بدون اسم' : 'Unnamed Customer'),
                                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (c.sourceTag != null && c.sourceTag!.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: c.sourceTag == 'excel_import'
                                                            ? cs.tertiaryContainer.withValues(alpha: 0.7)
                                                            : cs.secondaryContainer.withValues(alpha: 0.7),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        c.sourceTag == 'excel_import'
                                                            ? strings.excelSourceTag
                                                            : strings.manualSourceTag,
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: c.sourceTag == 'excel_import'
                                                              ? cs.onTertiaryContainer
                                                              : cs.onSecondaryContainer,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Phone Number
                                DataCell(
                                  Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          c.rawPhone,
                                          style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        if (c.isWhatsAppActive != null) ...[
                                          const SizedBox(width: 6),
                                          Tooltip(
                                            message: c.isWhatsAppActive == true
                                                ? (isAr ? 'رقم واتساب نشط ومفعل' : 'Active WhatsApp account')
                                                : (isAr ? 'لا يوجد حساب واتساب مرتبط' : 'No WhatsApp account found'),
                                            child: Icon(
                                              c.isWhatsAppActive == true ? Icons.verified_rounded : Icons.phonelink_erase_rounded,
                                              size: 16,
                                              color: c.isWhatsAppActive == true ? cs.primary : cs.error,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                // Invoices Count (Clickable pill for transactions)
                                DataCell(
                                  Tooltip(
                                    message: isAr ? 'عرض فواتير ومعاملات العميل' : 'View customer transactions & receipts',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showCustomerTransactionsDialog(
                                        context: context,
                                        customer: c,
                                        cs: cs,
                                        strings: strings,
                                        isAr: isAr,
                                        companyName: companyName,
                                        campaignName: campaignName,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.receipt_long_rounded, size: 14, color: cs.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${c.totalInvoices}',
                                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onPrimaryContainer),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Spend Amount
                                DataCell(
                                  Text(
                                    '${c.totalSpend.toStringAsFixed(1)} ${isAr ? "ج.م" : "EGP"}',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                // Prizes Won
                                DataCell(
                                  c.isWinner
                                      ? ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 240),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: cs.tertiaryContainer.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.emoji_events_rounded, size: 14, color: cs.tertiary),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    c.prizesWon.join(', '),
                                                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onTertiaryContainer),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Text('—', style: GoogleFonts.cairo(color: cs.onSurfaceVariant)),
                                ),
                                // Visited Branches
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      c.branches.isNotEmpty ? c.branches.join(', ') : '—',
                                      style: GoogleFonts.cairo(fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                // Last Visit
                                DataCell(Text(dateStr, style: GoogleFonts.cairo(fontSize: 12))),
                                // Action Buttons (Transactions, WhatsApp, Call)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Tooltip(
                                        message: isAr ? 'سجل المعاملات والفواتير' : 'Customer Transactions',
                                        child: IconButton(
                                          icon: Icon(Icons.receipt_long_rounded, size: 18, color: cs.tertiary),
                                          onPressed: () => _showCustomerTransactionsDialog(
                                            context: context,
                                            customer: c,
                                            cs: cs,
                                            strings: strings,
                                            isAr: isAr,
                                            companyName: companyName,
                                            campaignName: campaignName,
                                          ),
                                        ),
                                      ),
                                      Tooltip(
                                        message: strings.sendDirectWhatsApp,
                                        child: IconButton(
                                          icon: Icon(Icons.chat_bubble_rounded, size: 18, color: cs.primary),
                                          onPressed: () {
                                            _launchWhatsAppCampaign(
                                              targetContacts: [c],
                                              companyName: companyName,
                                              campaignName: campaignName,
                                              strings: strings,
                                              isAr: isAr,
                                            );
                                          },
                                        ),
                                      ),
                                      Tooltip(
                                        message: strings.callCustomerPhone,
                                        child: IconButton(
                                          icon: Icon(Icons.phone_rounded, size: 18, color: cs.secondary),
                                          onPressed: () async {
                                            final uri = Uri.parse('tel:${c.rawPhone}');
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    // Desktop Pagination Controls Footer
                    if (totalContacts > 0)
                      _buildPaginationFooter(
                        cs: cs,
                        strings: strings,
                        isAr: isAr,
                        totalContacts: totalContacts,
                        totalPages: totalPages,
                        safeCurrentPage: safeCurrentPage,
                        startIndex: startIndex,
                        endIndex: endIndex,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

  /// Modern M3 Pagination Controls Footer
  Widget _buildPaginationFooter({
    required ColorScheme cs,
    required AppStrings strings,
    required bool isAr,
    required int totalContacts,
    required int totalPages,
    required int safeCurrentPage,
    required int startIndex,
    required int endIndex,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          // Range counter (e.g. "عرض 1 - 50 من إجمالي 599 عميل")
          Text(
            strings.showingCustomersRange(startIndex + 1, endIndex, totalContacts),
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),

          // Controls Group (Rows per page + Page Navigators)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rows per page selector with M3ActionMenu
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.rowsPerPageLabel,
                    style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  M3ActionMenu(
                    tooltip: strings.rowsPerPageLabel,
                    anchorBuilder: (context, controller, child) {
                      return InkWell(
                        onTap: () => controller.isOpen ? controller.close() : controller.open(),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _rowsPerPage >= 999999 ? strings.allRowsOption : '$_rowsPerPage',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down_rounded, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      );
                    },
                    children: [
                      M3ActionMenu.item(
                        context: context,
                        label: '25',
                        isSelected: _rowsPerPage == 25,
                        onPressed: () => setState(() {
                          _rowsPerPage = 25;
                          _currentPage = 0;
                        }),
                      ),
                      M3ActionMenu.item(
                        context: context,
                        label: '50',
                        isSelected: _rowsPerPage == 50,
                        onPressed: () => setState(() {
                          _rowsPerPage = 50;
                          _currentPage = 0;
                        }),
                      ),
                      M3ActionMenu.item(
                        context: context,
                        label: '100',
                        isSelected: _rowsPerPage == 100,
                        onPressed: () => setState(() {
                          _rowsPerPage = 100;
                          _currentPage = 0;
                        }),
                      ),
                      M3ActionMenu.divider(),
                      M3ActionMenu.item(
                        context: context,
                        label: strings.allRowsOption,
                        isSelected: _rowsPerPage >= 999999,
                        onPressed: () => setState(() {
                          _rowsPerPage = 999999;
                          _currentPage = 0;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // First Page Button
              IconButton(
                icon: Icon(isAr ? Icons.last_page_rounded : Icons.first_page_rounded, size: 20),
                tooltip: isAr ? 'الصفحة الأولى' : 'First Page',
                onPressed: safeCurrentPage > 0
                    ? () => setState(() => _currentPage = 0)
                    : null,
              ),

              // Previous Page Button
              IconButton(
                icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 22),
                tooltip: strings.previousCustomer,
                onPressed: safeCurrentPage > 0
                    ? () => setState(() => _currentPage = safeCurrentPage - 1)
                    : null,
              ),

              // Page Indicator Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  strings.pageOfTotal(safeCurrentPage + 1, totalPages < 1 ? 1 : totalPages),
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),

              // Next Page Button
              IconButton(
                icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 22),
                tooltip: strings.nextCustomer,
                onPressed: safeCurrentPage < totalPages - 1
                    ? () => setState(() => _currentPage = safeCurrentPage + 1)
                    : null,
              ),

              // Last Page Button
              IconButton(
                icon: Icon(isAr ? Icons.first_page_rounded : Icons.last_page_rounded, size: 20),
                tooltip: isAr ? 'الصفحة الأخيرة' : 'Last Page',
                onPressed: safeCurrentPage < totalPages - 1
                    ? () => setState(() => _currentPage = totalPages - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mobile Customer Cards List with pagination support
  Widget _buildMobileCustomerCardsList(
    List<CustomerCampaignContact> contacts,
    ColorScheme cs,
    AppStrings strings,
    bool isAr,
    String companyName,
    String campaignName,
  ) {
    final maxChipWidth = (MediaQuery.of(context).size.width - 64).clamp(160.0, 500.0);
    final totalContacts = contacts.length;
    final totalPages = _rowsPerPage > 0 ? (totalContacts / _rowsPerPage).ceil() : 1;
    final safeCurrentPage = _currentPage < 0 ? 0 : (_currentPage >= totalPages ? (totalPages > 0 ? totalPages - 1 : 0) : _currentPage);
    final startIndex = totalContacts == 0 ? 0 : safeCurrentPage * _rowsPerPage;
    final int endIndex = (startIndex + _rowsPerPage > totalContacts) ? totalContacts : (startIndex + _rowsPerPage);
    final pagedContacts = totalContacts == 0 ? <CustomerCampaignContact>[] : contacts.sublist(startIndex, endIndex);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == pagedContacts.length) {
              if (totalPages <= 1) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 8, bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 20),
                      onPressed: safeCurrentPage > 0
                          ? () => setState(() => _currentPage = safeCurrentPage - 1)
                          : null,
                    ),
                    Text(
                      strings.pageOfTotal(safeCurrentPage + 1, totalPages < 1 ? 1 : totalPages),
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    IconButton.filledTonal(
                      icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 20),
                      onPressed: safeCurrentPage < totalPages - 1
                          ? () => setState(() => _currentPage = safeCurrentPage + 1)
                          : null,
                    ),
                  ],
                ),
              );
            }

            final c = pagedContacts[index];
            final isSelected = _selectedContactIds.contains(c.id);

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedContactIds.remove(c.id);
                  } else {
                    _selectedContactIds.add(c.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          activeColor: cs.primary,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedContactIds.add(c.id);
                              } else {
                                _selectedContactIds.remove(c.id);
                              }
                            });
                          },
                        ),
                        // Customer Avatar (Clickable for transactions)
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showCustomerTransactionsDialog(
                            context: context,
                            customer: c,
                            cs: cs,
                            strings: strings,
                            isAr: isAr,
                            companyName: companyName,
                            campaignName: campaignName,
                          ),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: cs.primary.withValues(alpha: 0.15),
                            child: Text(
                              c.name.isNotEmpty ? c.name.characters.first : 'ع',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: InkWell(
                                      onTap: () => _showCustomerTransactionsDialog(
                                        context: context,
                                        customer: c,
                                        cs: cs,
                                        strings: strings,
                                        isAr: isAr,
                                        companyName: companyName,
                                        campaignName: campaignName,
                                      ),
                                      child: Text(
                                        c.name.isNotEmpty ? c.name : (isAr ? 'عميل بدون اسم' : 'Unnamed Customer'),
                                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  if (c.sourceTag != null && c.sourceTag!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: c.sourceTag == 'excel_import'
                                            ? cs.tertiaryContainer.withValues(alpha: 0.7)
                                            : cs.secondaryContainer.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        c.sourceTag == 'excel_import'
                                            ? strings.excelSourceTag
                                            : strings.manualSourceTag,
                                        style: GoogleFonts.cairo(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: c.sourceTag == 'excel_import'
                                              ? cs.onTertiaryContainer
                                              : cs.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      c.rawPhone,
                                      style: GoogleFonts.robotoMono(fontSize: 12, color: cs.onSurfaceVariant),
                                    ),
                                    if (c.isWhatsAppActive != null) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        c.isWhatsAppActive == true ? Icons.verified_rounded : Icons.phonelink_erase_rounded,
                                        size: 14,
                                        color: c.isWhatsAppActive == true ? cs.primary : cs.error,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Quick Transactions button
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: cs.tertiaryContainer.withValues(alpha: 0.7),
                            foregroundColor: cs.onTertiaryContainer,
                            minimumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.receipt_long_rounded, size: 16),
                          tooltip: isAr ? 'سجل المعاملات والفواتير' : 'Transactions',
                          onPressed: () => _showCustomerTransactionsDialog(
                            context: context,
                            customer: c,
                            cs: cs,
                            strings: strings,
                            isAr: isAr,
                            companyName: companyName,
                            campaignName: campaignName,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Quick Phone Call button
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: cs.secondaryContainer.withValues(alpha: 0.7),
                            foregroundColor: cs.onSecondaryContainer,
                            minimumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 16),
                          onPressed: () async {
                            final uri = Uri.parse('tel:${c.rawPhone}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        // Quick WhatsApp button
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: cs.primaryContainer,
                            foregroundColor: cs.primary,
                            minimumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                          onPressed: () {
                            _launchWhatsAppCampaign(
                              targetContacts: [c],
                              companyName: companyName,
                              campaignName: campaignName,
                              strings: strings,
                              isAr: isAr,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showCustomerTransactionsDialog(
                            context: context,
                            customer: c,
                            cs: cs,
                            strings: strings,
                            isAr: isAr,
                            companyName: companyName,
                            campaignName: campaignName,
                          ),
                          child: _buildChip(
                            Icons.receipt_long_rounded,
                            '${c.totalInvoices} ${isAr ? "فواتير" : "inv"}',
                            cs,
                            accentColor: cs.primary,
                            maxWidth: maxChipWidth,
                          ),
                        ),
                        _buildChip(Icons.shopping_bag_rounded, '${c.totalSpend.toStringAsFixed(0)} ${isAr ? "ج.م" : "EGP"}', cs, maxWidth: maxChipWidth),
                        if (c.lastBranch.isNotEmpty)
                          _buildChip(Icons.storefront_rounded, c.lastBranch, cs, maxWidth: maxChipWidth),
                        if (c.isWinner)
                          _buildChip(
                            Icons.emoji_events_rounded,
                            c.prizesWon.join(', '),
                            cs,
                            accentColor: cs.tertiary,
                            maxWidth: maxChipWidth,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: pagedContacts.length + (totalPages > 1 ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String text, ColorScheme cs, {Color? accentColor, double? maxWidth}) {
    final color = accentColor ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (accentColor ?? cs.surfaceContainerHighest).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiItem {
  final IconData icon;
  final String title;
  final String value;
  final Color accentColor;

  const _KpiItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.accentColor,
  });
}
