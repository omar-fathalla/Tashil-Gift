import '../../features/admin/domain/event_model.dart';
import 'canonical_branch_resolver.dart';

/// Resolves the campaign branch a receipt belongs to.
/// Returns `id == null` when the branch is unknown or ambiguous;
/// callers must not guess the first branch (the server refuses ambiguous
/// stock decrements instead).
class ReceiptBranchResolution {
  final String? id;
  final String name;

  /// True when [id] is the one campaign branch for this receipt.
  final bool certain;

  const ReceiptBranchResolution(this.id, this.name, {this.certain = false});
}

class ReceiptBranchResolver {
  ReceiptBranchResolver._();

  static ReceiptBranchResolution resolve(EventModel? event, String branchDetected,
      {String receiptNumber = ''}) {
    final detectedRaw = branchDetected.trim();
    if (event == null || event.branchIds.isEmpty) {
      return ReceiptBranchResolution(null, detectedRaw);
    }
    final match = CanonicalBranchResolver.resolve(
      branchIds: event.branchIds,
      branchNames: event.branchNames,
      detectedName: detectedRaw,
      receiptNumber: receiptNumber,
    );
    if (match.certain && match.id != null) {
      return ReceiptBranchResolution(match.id, match.name, certain: true);
    }

    // Prize rows can name a branch the campaign list missed. Same rule:
    // store code, then exact / longest name. Never the first shorter sibling.
    if (event.allocatedPrizes.isNotEmpty) {
      final ids = <String>[];
      final names = <String>[];
      for (final p in event.allocatedPrizes) {
        final name = p.branchName.trim();
        if (name.isEmpty && p.branchId.trim().isEmpty) continue;
        ids.add(p.branchId.trim().isNotEmpty ? p.branchId.trim() : name);
        names.add(name.isNotEmpty ? name : p.branchId.trim());
      }
      final prize = CanonicalBranchResolver.resolve(
        branchIds: ids,
        branchNames: names,
        detectedName: detectedRaw,
        receiptNumber: receiptNumber,
      );
      if (prize.certain && prize.id != null) {
        return ReceiptBranchResolution(prize.id, prize.name, certain: true);
      }
    }

    if (event.branchIds.length == 1) {
      final name = event.branchNames.isNotEmpty ? event.branchNames.first : detectedRaw;
      return ReceiptBranchResolution(event.branchIds.first, name, certain: true);
    }
    return ReceiptBranchResolution(null, detectedRaw);
  }

  /// Name and id written on a receipt. A certain match stores the campaign
  /// name. An uncertain match stores the detected text and an empty id.
  static Map<String, String> firestoreFields(
    EventModel? event, {
    required String detectedName,
    required String receiptNumber,
  }) {
    final resolved = resolve(event, detectedName, receiptNumber: receiptNumber);
    final name = resolved.certain && resolved.name.trim().isNotEmpty
        ? resolved.name.trim()
        : detectedName.trim();
    return {
      'branch_detected': name,
      'canonical_branch': name,
      'branch_id': resolved.id ?? '',
    };
  }
}
