import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/firebase_service.dart';
import '../../domain/campaign_content.dart';
import '../../domain/event_model.dart';

/// TAG-56: loads a campaign's products and prompt (events/{id}/content)
/// before it is opened for editing. Returns null, after telling the admin,
/// when they cannot be loaded, so the editor never opens with an empty list
/// that a save would then write back.
Future<EventModel?> loadCampaignContentForEdit(BuildContext context, WidgetRef ref, EventModel event) async {
  try {
    return await CampaignContentStore(ref.read(firestoreProvider)).hydrate(event);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is CampaignContentUnavailable ? e.toString() : 'تعذر تحميل منتجات وبرومبت الحملة. جرّب تاني.',
              style: GoogleFonts.cairo()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return null;
  }
}
