import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/arabic_numbers_utils.dart';
import 'whatsapp_campaign_dispatcher_dialog.dart';

/// Name and mobile table for the company-supervisors audience.
///
/// Selection and sending stay with the marketing screen so the existing
/// campaign dispatcher, including a PDF attachment, is reused.
class CompanySupervisorsAudienceTable extends StatelessWidget {
  final List<CustomerCampaignContact> contacts;
  final Set<String> selectedIds;
  final int currentPage;
  final int rowsPerPage;
  final bool isMobile;
  final bool isAr;
  final AppStrings strings;
  final ColorScheme colorScheme;
  final ValueChanged<String> onToggle;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<CustomerCampaignContact> onSend;

  const CompanySupervisorsAudienceTable({
    super.key,
    required this.contacts,
    required this.selectedIds,
    required this.currentPage,
    required this.rowsPerPage,
    required this.isMobile,
    required this.isAr,
    required this.strings,
    required this.colorScheme,
    required this.onToggle,
    required this.onPageChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final total = contacts.length;
    final totalPages = rowsPerPage > 0 ? (total / rowsPerPage).ceil() : 1;
    final safePage = currentPage < 0
        ? 0
        : (currentPage >= totalPages ? (totalPages > 0 ? totalPages - 1 : 0) : currentPage);
    final start = total == 0 ? 0 : safePage * rowsPerPage;
    final end = (start + rowsPerPage > total) ? total : start + rowsPerPage;
    final page = total == 0 ? <CustomerCampaignContact>[] : contacts.sublist(start, end);
    final horizontal = isMobile ? 14.0 : 24.0;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMobile)
                  for (final contact in page) _mobileRow(contact)
                else
                  _desktopTable(context, page),
                if (total > 0) _pager(safePage, totalPages, start, end, total),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopTable(BuildContext context, List<CustomerCampaignContact> page) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth < 720 ? 720 : constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
              horizontalMargin: 16,
              columnSpacing: 24,
              columns: [
                const DataColumn(label: SizedBox(width: 24)),
                DataColumn(label: Text(strings.companySupervisorName, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(strings.companySupervisorMobile, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(strings.companySupervisorAlternate, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(strings.actions, style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
              ],
              rows: [
                for (final contact in page)
                  DataRow(
                    selected: selectedIds.contains(contact.id),
                    onSelectChanged: (_) => onToggle(contact.id),
                    cells: [
                      DataCell(Checkbox(
                        value: selectedIds.contains(contact.id),
                        activeColor: colorScheme.primary,
                        onChanged: (_) => onToggle(contact.id),
                      )),
                      DataCell(_nameCell(contact)),
                      DataCell(_phoneCell(contact)),
                      DataCell(_alternateCell(contact)),
                      DataCell(_actions(contact)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mobileRow(CustomerCampaignContact contact) {
    final selected = selectedIds.contains(contact.id);
    return InkWell(
      onTap: () => onToggle(contact.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondaryContainer : null,
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              activeColor: colorScheme.primary,
              onChanged: (_) => onToggle(contact.id),
            ),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name.toEnglishDigits(),
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _phoneCell(contact),
                if (contact.alternateNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _alternateCell(contact),
                ],
              ],
            )),
            _actions(contact),
          ],
        ),
      ),
    );
  }

  Widget _nameCell(CustomerCampaignContact contact) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Text(
        contact.name.toEnglishDigits(),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _phoneCell(CustomerCampaignContact contact) {
    final phone = contact.rawPhone.toEnglishDigits();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(phone, style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _alternateCell(CustomerCampaignContact contact) {
    final text = contact.alternateNames.map((name) => name.toEnglishDigits()).join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Text(
        text.isEmpty ? '—' : text,
        style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _actions(CustomerCampaignContact contact) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: strings.sendDirectWhatsApp,
          icon: Icon(Icons.chat_bubble_rounded, color: colorScheme.primary),
          onPressed: () => onSend(contact),
        ),
        IconButton(
          tooltip: strings.callCustomerPhone,
          icon: Icon(Icons.phone_rounded, color: colorScheme.secondary),
          onPressed: () async {
            final uri = Uri.parse('tel:${contact.rawPhone.toEnglishDigits()}');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),
      ],
    );
  }

  Widget _pager(int page, int totalPages, int start, int end, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.showingSupervisorsRange(start + 1, end, total),
              style: GoogleFonts.cairo(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: strings.previousCustomer,
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
            icon: Icon(isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
          ),
          Text(
            strings.pageOfTotal(page + 1, totalPages < 1 ? 1 : totalPages),
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: strings.nextCustomer,
            onPressed: page < totalPages - 1 ? () => onPageChanged(page + 1) : null,
            icon: Icon(isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
