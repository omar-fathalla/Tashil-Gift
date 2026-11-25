import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/firebase_scope.dart';
import '../../domain/campaign_dry_run.dart';
import '../../domain/event_model.dart';

/// C-05 "جرّب على فاتورة": checks receipt data against the campaign as it is
/// in the editor, with the same server check a real claim runs. Nothing is
/// written: no stock, no claim, no receipt.
class CampaignTryReceiptDialog extends StatefulWidget {
  final EventModel campaign;

  const CampaignTryReceiptDialog({super.key, required this.campaign});

  static Future<void> show(BuildContext context, EventModel campaign) => showDialog<void>(
        context: context,
        builder: (_) => CampaignTryReceiptDialog(campaign: campaign),
      );

  @override
  State<CampaignTryReceiptDialog> createState() => _CampaignTryReceiptDialogState();
}

class _LineControllers {
  final name = TextEditingController();
  final price = TextEditingController();
  final qty = TextEditingController(text: '1');
  bool target = true;

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

class _CampaignTryReceiptDialogState extends State<CampaignTryReceiptDialog> {
  bool _useStored = false;
  final _receiptId = TextEditingController();
  final _date = TextEditingController();
  final List<_LineControllers> _lines = [_LineControllers()];
  bool _busy = false;
  DryRunResult? _result;
  String? _error;

  @override
  void dispose() {
    _receiptId.dispose();
    _date.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<DryRunLine> _manualLines() => [
        for (final l in _lines)
          if (l.name.text.trim().isNotEmpty)
            DryRunLine(
              name: l.name.text,
              price: double.tryParse(l.price.text.trim()) ?? 0,
              quantity: int.tryParse(l.qty.text.trim()) ?? 1,
              isTargetCompany: l.target,
            ),
      ];

  Future<void> _run() async {
    final lines = _manualLines();
    if (_useStored ? _receiptId.text.trim().isEmpty : lines.isEmpty) {
      setState(() => _error = _useStored ? 'اكتب رقم الفاتورة (المعرّف) الأول.' : 'أضف صنف واحد على الأقل.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final payload = CampaignDryRun.request(
        campaign: widget.campaign,
        receiptId: _useStored ? _receiptId.text : null,
        receipt: _useStored ? null : CampaignDryRun.receiptPayload(receiptDate: _date.text, lines: lines),
      );
      final res = await scopedFunctions()
          .httpsCallable(CampaignDryRun.callableName, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<dynamic>(payload);
      final data = res.data;
      if (!mounted) return;
      setState(() => _result = data is Map ? DryRunResult.fromMap(data) : null);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'not-found' && (e.message ?? '').isEmpty
          ? 'خدمة التجربة مش متاحة لسه على السيرفر.'
          : ((e.message ?? '').isNotEmpty ? e.message! : 'تعذر تشغيل التجربة، حاول تاني.'));
    } catch (e) {
      if (!mounted) return;
      debugPrint('C-05 dry run failed: $e');
      setState(() => _error = 'تعذر تشغيل التجربة، حاول تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _resultCard(ColorScheme cs, TextTheme tt) {
    final r = _result!;
    final good = r.ok;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: good ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(good ? Icons.check_circle_rounded : Icons.cancel_rounded, color: good ? cs.onPrimaryContainer : cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(good ? 'الفاتورة مؤهلة حسب شروط الحملة' : 'الفاتورة مش مؤهلة',
                style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: good ? cs.onPrimaryContainer : cs.onErrorContainer)),
          ),
        ]),
        if (!good && (r.message ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.message!, style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer)),
        ],
        if (good && r.serverUnits != null) ...[
          const SizedBox(height: 6),
          Text('عدد الهدايا المسموح بها للفاتورة دي: ${r.serverUnits}', style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
        ],
        if (good && r.mode == 'consuming')
          Text('في وضع السلم الاستهلاكي عدد الجولات بيتحدد وقت الصرف.', style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer)),
        const SizedBox(height: 6),
        Text(
          'تجربة فقط: لم يُخصم أي رصيد ولم تُسجَّل أي فاتورة أو جائزة.${r.campaignActive ? '' : ' (الحملة نفسها مش مفعّلة حاليًا؛ التجربة اعتبرتها مفعّلة.)'}',
          style: tt.bodySmall?.copyWith(color: good ? cs.onPrimaryContainer : cs.onErrorContainer),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('جرّب الحملة على فاتورة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('بيتم الفحص بنفس شروط السيرفر بتاعة صرف الجوائز، على إعدادات الحملة الحالية في الشاشة (حتى لو مش محفوظة).',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('إدخال أصناف'), icon: Icon(Icons.edit_note_rounded)),
                  ButtonSegment(value: true, label: Text('فاتورة مرفوعة'), icon: Icon(Icons.receipt_long_rounded)),
                ],
                selected: {_useStored},
                onSelectionChanged: _busy ? null : (s) => setState(() => _useStored = s.first),
              ),
              const SizedBox(height: 12),
              if (_useStored)
                TextField(
                  controller: _receiptId,
                  decoration: const InputDecoration(
                    labelText: 'معرّف الفاتورة (من سجل الفواتير)',
                    helperText: 'بيتقرأ تاريخ الفاتورة ووقت رفعها وأصنافها زي ما اتسجلت.',
                    border: OutlineInputBorder(),
                  ),
                )
              else ...[
                TextField(
                  controller: _date,
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الفاتورة كما هو مطبوع (اختياري)',
                    hintText: 'مثال: 24/11/2026',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _lines[i].name,
                          decoration: const InputDecoration(labelText: 'اسم الصنف', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _lines[i].price,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'سعر الوحدة', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _lines[i].qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'كمية', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      Tooltip(
                        message: 'منتج الشركة صاحبة الحملة',
                        child: Checkbox(
                          value: _lines[i].target,
                          onChanged: (v) => setState(() => _lines[i].target = v ?? true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف الصنف',
                        onPressed: _lines.length == 1
                            ? null
                            : () => setState(() {
                                  _lines.removeAt(i).dispose();
                                }),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ]),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_LineControllers())),
                    icon: const Icon(Icons.add_rounded),
                    label: Text('إضافة صنف', style: GoogleFonts.cairo()),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: tt.bodyMedium?.copyWith(color: cs.error)),
                ),
              if (_result != null) _resultCard(cs, tt),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('إغلاق', style: GoogleFonts.cairo())),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text('جرّب', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
