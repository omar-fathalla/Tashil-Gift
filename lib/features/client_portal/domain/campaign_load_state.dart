/// TAG-81: why the rep link could not show a usable campaign.
///
/// Replaces the old free-text `_errorMessage`, which sent every load failure
/// to `CampaignSuspendedScreen` ("الحملة موقوفة").
library;

import '../../../core/services/receipt_save_failure.dart' show receiptErrorCode;

enum CampaignLoadState {
  /// A campaign is loaded (it may still be paused; `build` checks the event).
  ok,

  /// The link has neither a company slug nor an event id.
  noLink,

  /// No active campaign on this link.
  noCampaign,

  /// Company link: active campaigns exist but all are paused for reps
  /// (`isPromoterActive == false`).
  promoterPaused,

  /// Single campaign read denied while a session exists. The rules deny
  /// anonymous reads of any campaign with `isActive != true`, so this means
  /// the campaign is paused or not available.
  suspended,

  /// No Firebase session (e.g. anonymous auth disabled or sign-in failed).
  sessionError,

  /// Anything else: network, unavailable, a denied company query, etc.
  loadError,
}

bool isPermissionDeniedError(Object error) =>
    receiptErrorCode(error) == 'permission-denied';

/// Single place that maps a load error to a state.
///
/// [hasSession]: a Firebase user exists right now.
/// [singleDoc]: the failed read was one campaign document (not a query).
CampaignLoadState classifyCampaignLoadError(
  Object error, {
  required bool hasSession,
  required bool singleDoc,
}) {
  if (!hasSession) return CampaignLoadState.sessionError;
  if (singleDoc && isPermissionDeniedError(error)) {
    return CampaignLoadState.suspended;
  }
  return CampaignLoadState.loadError;
}

/// Shown by `CampaignSuspendedScreen` (unchanged screen).
bool showsSuspendedScreen(CampaignLoadState s) =>
    s == CampaignLoadState.suspended || s == CampaignLoadState.promoterPaused;

/// Shown by `PortalDataErrorView` with a retry button.
bool showsLoadErrorView(CampaignLoadState s) =>
    s == CampaignLoadState.noLink ||
    s == CampaignLoadState.noCampaign ||
    s == CampaignLoadState.sessionError ||
    s == CampaignLoadState.loadError;

/// The technical code is shown (small) only for these states.
bool showsErrorCode(CampaignLoadState s) =>
    s == CampaignLoadState.sessionError || s == CampaignLoadState.loadError;

/// Short technical code shown under the message, e.g. `operation-not-allowed`.
String campaignLoadErrorCode(Object? error) =>
    error == null ? 'no-session' : receiptErrorCode(error);

String? campaignLoadMessage(CampaignLoadState s) {
  switch (s) {
    case CampaignLoadState.noLink:
      return 'رابط الحملة غير مكتمل.';
    case CampaignLoadState.noCampaign:
      return 'لا توجد حملة متاحة على هذا الرابط حاليًا.';
    case CampaignLoadState.sessionError:
      return 'تعذر بدء الجلسة. حاول مرة أخرى.';
    case CampaignLoadState.loadError:
      return 'تعذر تحميل بيانات الحملة. تحقق من الاتصال ثم حاول مرة أخرى.';
    case CampaignLoadState.ok:
    case CampaignLoadState.promoterPaused:
    case CampaignLoadState.suspended:
      return null;
  }
}
