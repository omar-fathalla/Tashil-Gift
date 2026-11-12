import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/localization/app_strings.dart';
import '../../domain/company_supervisor.dart';
import '../../domain/company_supervisor_import.dart';
import '../../domain/company_supervisors_service.dart';

/// Admin re-import of the company-supervisors workbook.
///
/// Nothing is written until the signed-in admin confirms. The same parser the
/// offline script uses collapses duplicate phones before the write.
class CompanySupervisorImportDialog extends StatefulWidget {
  final AppStrings strings;

  const CompanySupervisorImportDialog({super.key, required this.strings});

  @override
  State<CompanySupervisorImportDialog> createState() => _CompanySupervisorImportDialogState();
}

class _CompanySupervisorImportDialogState extends State<CompanySupervisorImportDialog> {
  final CompanySupervisorsService _service = CompanySupervisorsService();
  bool _parsing = false;
  bool _saving = false;
  bool _replaceMissing = false;
  String? _fileName;
  CompanySupervisorImportResult? _result;

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() {
      _parsing = true;
      _fileName = file.name;
      _result = null;
    });
    final parsed = parseCompanySupervisorWorkbook(bytes, fileName: file.name);
    if (!mounted) return;
    setState(() {
      _parsing = false;
      _result = parsed;
    });
  }

  Future<void> _save() async {
    final parsed = _result;
    if (parsed == null || !parsed.isSuccess || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _service.upsertAll(
        parsed.supervisors.map(CompanySupervisor.fromImport).toList(),
        replaceMissing: _replaceMissing,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.strings.companySupervisorsSaveFailed} $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final cs = Theme.of(context).colorScheme;
    final parsed = _result;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(strings.importCompanySupervisors, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: width < 600 ? width : 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.importCompanySupervisorsHelp,
                style: GoogleFonts.cairo(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _parsing ? null : _pick,
                icon: _parsing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_rounded),
                label: Text(
                  _fileName ?? strings.selectExcelOrCsvFile,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
              if (parsed != null) ...[
                const SizedBox(height: 16),
                if (parsed.errorMessage != null)
                  Text(parsed.errorMessage!, style: GoogleFonts.cairo(color: cs.error))
                else ...[
                  Text(
                    strings.companySupervisorsImportSummary(
                      parsed.sourceRowCount,
                      parsed.uniqueCount,
                      parsed.duplicateRowCount,
                    ),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  if (parsed.invalidRowCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      strings.companySupervisorsInvalidRows(parsed.invalidRowCount),
                      style: GoogleFonts.cairo(color: cs.error),
                    ),
                  ],
                  if (parsed.duplicateGroups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(strings.companySupervisorsDuplicateTitle, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final group in parsed.duplicateGroups)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${group.mobile} · ${group.keptName}'
                          '${group.alternateNames.isEmpty ? '' : ' · ${group.alternateNames.join(' / ')}'}',
                          style: GoogleFonts.cairo(fontSize: 12),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _replaceMissing,
                    onChanged: _saving ? null : (value) => setState(() => _replaceMissing = value ?? false),
                    title: Text(strings.companySupervisorsReplaceMissing, style: GoogleFonts.cairo(fontSize: 13)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
        FilledButton(
          onPressed: parsed != null && parsed.isSuccess && !_saving ? _save : null,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(strings.companySupervisorsSaveList, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
