import '../../features/admin/domain/event_model.dart';
import '../services/company_gifts_service.dart';

/// Resolves the campaign branch a receipt belongs to from the AI-detected
/// branch name. Returns `id == null` when the branch is unknown or ambiguous;
/// callers must not guess the first branch (the server refuses ambiguous
/// stock decrements instead).
class ReceiptBranchResolution {
  final String? id;
  final String name;
  const ReceiptBranchResolution(this.id, this.name);
}

class ReceiptBranchResolver {
  ReceiptBranchResolver._();

  static ReceiptBranchResolution resolve(EventModel? event, String branchDetected) {
    final detectedRaw = branchDetected.trim();
    if (event == null || event.branchIds.isEmpty) {
      return ReceiptBranchResolution(null, detectedRaw);
    }
    final detected = CompanyGiftsService.normalizeBranchToken(detectedRaw);
    if (detected.isNotEmpty) {
      for (int i = 0; i < event.branchNames.length && i < event.branchIds.length; i++) {
        final n = CompanyGiftsService.normalizeBranchToken(event.branchNames[i]);
        if (n.isNotEmpty && (n == detected || n.contains(detected) || detected.contains(n))) {
          return ReceiptBranchResolution(event.branchIds[i], event.branchNames[i]);
        }
      }
      for (final p in event.allocatedPrizes) {
        final n = CompanyGiftsService.normalizeBranchToken(p.branchName);
        if (n.isNotEmpty && (n == detected || n.contains(detected) || detected.contains(n))) {
          return ReceiptBranchResolution(
            p.branchId.isNotEmpty ? p.branchId : p.branchName,
            p.branchName.trim().isNotEmpty ? p.branchName.trim() : detectedRaw,
          );
        }
      }
    }
    if (event.branchIds.length == 1) {
      final name = event.branchNames.isNotEmpty ? event.branchNames.first : detectedRaw;
      return ReceiptBranchResolution(event.branchIds.first, name);
    }
    return ReceiptBranchResolution(null, detectedRaw);
  }
}
