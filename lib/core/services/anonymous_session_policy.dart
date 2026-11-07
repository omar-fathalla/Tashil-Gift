/// Decides which entry routes need a Firebase anonymous session.
///
/// Field reps and portal users open public links without a login form, so
/// those routes keep Anonymous Auth. Admin/staff routes (`/`, `/admin`,
/// `/login`, `/auth`) sign in with email and must not create a throwaway
/// anonymous user on every visit (audit item M4).
const Set<String> kAnonymousSessionRoots = {
  'event', 'e', // direct event links
  'submit', 'c', 'client', 'promoter', // receipt upload links
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
