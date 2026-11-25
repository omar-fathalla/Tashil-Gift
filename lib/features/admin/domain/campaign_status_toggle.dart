import 'package:cloud_firestore/cloud_firestore.dart';

/// TAG-18: what the admin dashboard switch writes on a campaign.
///
/// Turning a campaign off marks it `pausedManually`, so the daily
/// auto-activate (Cloud Function, Cairo 00:10) never turns it back on.
/// Turning it on clears the mark. Both record who and when in
/// `statusUpdatedAt` / `statusUpdatedBy` (the system writes
/// 'system:auto-activate' or 'system:auto-close' there).
class CampaignStatusToggle {
  const CampaignStatusToggle._();

  static const String fieldPausedManually = 'pausedManually';
  static const String fieldStatusUpdatedAt = 'statusUpdatedAt';
  static const String fieldStatusUpdatedBy = 'statusUpdatedBy';

  /// The update for the switch. [timestamp] defaults to the server time.
  static Map<String, Object?> patch({
    required bool active,
    required String uid,
    Object? timestamp,
  }) =>
      {
        'isActive': active,
        fieldPausedManually: !active,
        fieldStatusUpdatedAt: timestamp ?? FieldValue.serverTimestamp(),
        fieldStatusUpdatedBy: uid,
      };
}
