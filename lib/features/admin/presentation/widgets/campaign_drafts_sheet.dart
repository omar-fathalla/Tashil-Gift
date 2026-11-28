import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/firebase_service.dart';
import '../../domain/campaign_draft.dart';
import '../create_event_screen.dart';

/// C-05: staff list of saved campaign drafts (open to continue, or delete).
class CampaignDraftsSheet extends ConsumerWidget {
  const CampaignDraftsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const FractionallySizedBox(heightFactor: 0.8, child: CampaignDraftsSheet()),
      );

  static String _when(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _open(BuildContext context, WidgetRef ref, CampaignDraft stored) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // TAG-65: a large draft keeps its products / prompt in content docs.
    final CampaignDraft draft;
    try {
      draft = await CampaignDraftStore(ref.read(firestoreProvider)).hydrate(stored);
    } catch (e) {
      debugPrint('TAG-65 draft content load failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحميل منتجات المسودة. تأكد من النت وجرّب تاني.', style: GoogleFonts.cairo())),
      );
      return;
    }
    if (!context.mounted) return;
    if (draft.isEditDraft && draft.baseEvent == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('المسودة ناقصة بيانات الحملة الأصلية؛ احذفها وابدأ التعديل من الحملة.', style: GoogleFonts.cairo())),
      );
      return;
    }
    nav.pop();
    await nav.push(MaterialPageRoute(
      builder: (_) => CreateEventScreen(eventToEdit: draft.baseEvent, resumeDraft: draft),
    ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, CampaignDraft draft) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف المسودة؟', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text('هتتحذف المسودة "${draft.eventName}" بس. الحملة الأصلية (لو موجودة) مش هتتأثر.',
            style: GoogleFonts.cairo()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('إلغاء', style: GoogleFonts.cairo())),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('حذف', style: GoogleFonts.cairo())),
        ],
      ),
    );
    if (ok != true) return;
    await CampaignDraftStore(ref.read(firestoreProvider)).delete(draft.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مسودات الحملات', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('المسودة مش ظاهرة للمندوبين ولا الفروع ولا بوابة الشركة، ومش بتدخل في الفواتير أو الإحصائيات لحد ما تتفعّل الحملة.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<CampaignDraft>>(
              stream: CampaignDraftStore(ref.read(firestoreProvider)).watchAll(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('تعذر تحميل المسودات', style: GoogleFonts.cairo(color: cs.error)));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final drafts = snap.data!;
                if (drafts.isEmpty) {
                  return Center(child: Text('لا توجد مسودات', style: GoogleFonts.cairo(color: cs.onSurfaceVariant)));
                }
                return ListView.separated(
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = drafts[i];
                    return ListTile(
                      leading: Icon(d.isEditDraft ? Icons.edit_note_rounded : Icons.note_add_outlined, color: cs.primary),
                      title: Text(d.eventName.isEmpty ? 'مسودة بدون اسم' : d.eventName, style: GoogleFonts.cairo()),
                      subtitle: Text(
                        [
                          d.isEditDraft ? 'تعديل على حملة موجودة' : 'حملة جديدة',
                          if (d.companySlug.isNotEmpty) d.companySlug,
                          _when(d.updatedAt),
                        ].join(' · '),
                        style: GoogleFonts.cairo(fontSize: 12),
                      ),
                      onTap: () => _open(context, ref, d),
                      trailing: IconButton(
                        tooltip: 'حذف المسودة',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(context, ref, d),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
