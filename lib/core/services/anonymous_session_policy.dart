/// Decides which entry routes need a Firebase anonymous session.
///
/// Public upload links and the rep app entry keep Anonymous Auth so receipt
/// writes stay on the current rules. The `/rep` screen adds an app-level
/// `rep_uploader` login; it does not replace the anonymous Firebase user.
/// Admin/staff routes (`/`, `/admin`, `/login`, `/auth`) sign in with email
/// and must not create a throwaway anonymous user on every visit (audit item M4).
const Set<String> kAnonymousSessionRoots = {
  'event', 'e', // direct event links
  'submit', 'c', 'client', 'promoter', // receipt upload links
  'rep', 'mandoub', 'uploader', // store/rep entry (login gate + anonymous upload)
  'portal', 'p', 'company', // company manager portal
  'ops', 'agency', 'operations', // agency ops portal
};

/// Returns the first path segment of [uri], honouring legacy hash routes
/// such as `/#/c?company=x`.
String entryRouteRoot(Uri uri) {
  var path = uri.path;
  final fragment = uri.fragment;
  if ((path.isEmpty || path == '/') && fragment.isNotEmpty) {
    path = fragment.replaceFirst(RegExp(r'^!?'), '').split('?').first;
  }
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.first.toLowerCase();
}

bool routeNeedsAnonymousSession(Uri uri) =>
    kAnonymousSessionRoots.contains(entryRouteRoot(uri));
