import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../security/password_hash.dart';
import 'firebase_service.dart';

/// Role types for Partner Portals with strict role isolation.
/// - [brandManager]: Accesses Brand Executive Portal (`/portal/:slug`) — Read-Only on Stock Balances.
/// - [agencyOps]: Accesses Agency Operations Portal (`/ops/:slug`, `/ep/:id`) — Full Read/Write on Stock Balances.
/// - [repUploader]: Shared field-rep account (`/rep/:slug`) — receipt upload only. Not `agency_ops`.
enum PartnerPortalRole {
  brandManager('brand_manager'),
  agencyOps('agency_ops'),
  repUploader('rep_uploader');

  final String value;
  const PartnerPortalRole(this.value);

  static PartnerPortalRole fromString(String? val) {
    switch (val) {
      case 'brand_manager':
        return PartnerPortalRole.brandManager;
      case 'rep_uploader':
        return PartnerPortalRole.repUploader;
      case 'agency_ops':
      default:
        return PartnerPortalRole.agencyOps;
    }
  }
}

/// Represents an authenticated Partner Portal session.
class PartnerPortalSession {
  final String companySlug;
  final PartnerPortalRole role;
  final String username;
  final int credentialVersion;
  final String? lockedEventId;
  final bool isCampaignTier;
  final DateTime authenticatedAt;

  const PartnerPortalSession({
    required this.companySlug,
    required this.role,
    required this.username,
    required this.credentialVersion,
    this.lockedEventId,
    this.isCampaignTier = false,
    required this.authenticatedAt,
  });

  Map<String, dynamic> toJson() => {
        'companySlug': companySlug,
        'role': role.value,
        'username': username,
        'credentialVersion': credentialVersion,
        'lockedEventId': lockedEventId,
        'isCampaignTier': isCampaignTier,
        'authenticatedAt': authenticatedAt.toIso8601String(),
      };

  factory PartnerPortalSession.fromJson(Map<String, dynamic> json) {
    return PartnerPortalSession(
      companySlug: (json['companySlug'] ?? '').toString().trim().toLowerCase(),
      role: PartnerPortalRole.fromString(json['role']?.toString()),
      username: (json['username'] ?? '').toString(),
      credentialVersion: (json['credentialVersion'] as num?)?.toInt() ?? 1,
      lockedEventId: json['lockedEventId']?.toString(),
      isCampaignTier: json['isCampaignTier'] == true,
      authenticatedAt: DateTime.tryParse(json['authenticatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Resolved credential configuration for a company or campaign.
class ResolvedPortalCredentials {
  final String companySlug;
  final String companyName;
  final String brandManagerUsername;
  final String brandManagerPassword;
  final int brandCredentialVersion;
  final String agencyOpsUsername;
  final String agencyOpsPassword;
  final int agencyCredentialVersion;

  // Tier 2 Campaign Override (Optional)
  final String? eventId;
  final String? eventName;
  final bool hasCustomAgencyCredentials;
  final String customAgencyUsername;
  final String customAgencyPassword;
  final int customAgencyCredentialVersion;

  /// Shared مندوب account. The hash is never a password to display.
  final String repUploaderUsername;
  final String repUploaderPasswordHash;
  final int repUploaderCredentialVersion;
  final bool repUploaderConfigured;

  /// Public company logo (https) for portal branding; may be empty.
  final String companyLogoUrl;

  /// True when resolved through the partnerPortalInfo callable (non-admin
  /// visitor). Usernames/passwords are then empty and login must go through
  /// partnerPortalLogin.
  final bool serverResolved;

  const ResolvedPortalCredentials({
    required this.companySlug,
    required this.companyName,
    required this.brandManagerUsername,
    required this.brandManagerPassword,
    required this.brandCredentialVersion,
    required this.agencyOpsUsername,
    required this.agencyOpsPassword,
    required this.agencyCredentialVersion,
    this.eventId,
    this.eventName,
    this.hasCustomAgencyCredentials = false,
    this.customAgencyUsername = '',
    this.customAgencyPassword = '',
    this.customAgencyCredentialVersion = 1,
    this.repUploaderUsername = '',
    this.repUploaderPasswordHash = '',
    this.repUploaderCredentialVersion = 1,
    this.repUploaderConfigured = false,
    this.companyLogoUrl = '',
    this.serverResolved = false,
  });

  String get effectiveAgencyUsername =>
      (hasCustomAgencyCredentials && customAgencyUsername.trim().isNotEmpty)
          ? customAgencyUsername.trim()
          : agencyOpsUsername.trim();

  String get effectiveAgencyPassword =>
      (hasCustomAgencyCredentials && customAgencyPassword.trim().isNotEmpty)
          ? customAgencyPassword.trim()
          : agencyOpsPassword.trim();

  int get effectiveAgencyVersion =>
      hasCustomAgencyCredentials ? customAgencyCredentialVersion : agencyCredentialVersion;
}

/// Result of a login attempt.
class PortalAuthResult {
  final bool isSuccess;
  final PartnerPortalSession? session;
  final String? errorMessageAr;
  final String? errorMessageEn;

  const PortalAuthResult._({
    required this.isSuccess,
    this.session,
    this.errorMessageAr,
    this.errorMessageEn,
  });

  factory PortalAuthResult.success(PartnerPortalSession session) =>
      PortalAuthResult._(isSuccess: true, session: session);

  factory PortalAuthResult.failure({
    required String errorMessageAr,
    required String errorMessageEn,
  }) =>
      PortalAuthResult._(
        isSuccess: false,
        errorMessageAr: errorMessageAr,
        errorMessageEn: errorMessageEn,
      );
}

final partnerPortalAuthServiceProvider = Provider<PartnerPortalAuthService>((ref) {
  try {
    final firestore = ref.watch(firestoreProvider);
    return PartnerPortalAuthService(
      firestore: firestore,
      functions: ref.watch(firebaseFunctionsProvider),
      auth: ref.watch(firebaseAuthProvider),
    );
  } catch (_) {
    return PartnerPortalAuthService(firestore: null);
  }
});

/// Notifier tracking active in-memory portal sessions to trigger immediate UI updates on login/logout.
final partnerPortalSessionEpochProvider = StateProvider<int>((ref) => 0);

/// Tracks whether the System Admin preview bypass has been explicitly revoked via "تسجيل الخروج من البوابة".
/// When true, the portal login guard strictly enforces authentication even for logged-in Firebase admins.
final partnerPortalAdminBypassRevokedProvider = StateProvider<bool>((ref) => false);

class PartnerPortalAuthService {
  final FirebaseFirestore? _firestore;

  /// In-memory session cache for the active browser tab / app lifecycle.
  static final Map<String, PartnerPortalSession> _memorySessions = {};
  static final Map<String, Map<String, dynamic>> _memoryCompanyCredentials = {};
  static final Map<String, Map<String, dynamic>> _memoryEventOverrides = {};

  static void clearMemorySessions() {
    _memorySessions.clear();
    _memoryCompanyCredentials.clear();
    _memoryEventOverrides.clear();
  }

  PartnerPortalAuthService({FirebaseFirestore? firestore, FirebaseFunctions? functions, FirebaseAuth? auth})
      : _firestore = firestore,
        _functions = functions,
        _auth = auth;

  final FirebaseFunctions? _functions;
  final FirebaseAuth? _auth;

  static const Set<String> _staffRoles = {'admin', 'super_admin'};

  /// Signs this browser into Firebase as the portal partner (custom token with
  /// role/companySlug claims) so Firestore rules grant company-scoped reads.
  /// Never replaces a signed-in admin session.
  Future<bool> _adoptPortalIdentity(String? customToken) async {
    final auth = _auth;
    if (auth == null) return true;
    final current = auth.currentUser;
    if (current != null && !current.isAnonymous) {
      try {
        final claims = (await current.getIdTokenResult()).claims ?? const {};
        if (_staffRoles.contains(claims['role'])) return true;
      } catch (_) {}
    }
    if (customToken == null || customToken.isEmpty) return false;
    try {
      await auth.signInWithCustomToken(customToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when the Firebase user can read this portal's data: a staff admin,
  /// or a partner token for the same company, portal role and credential version.
  Future<bool> _firebaseIdentityMatches(PartnerPortalSession session) async {
    final auth = _auth;
    if (auth == null || _functions == null) return true;
    // Receipt upload stays on anonymous auth until rules explicitly allow the
    // upload claim. Revocation is the credentialVersion check.
    if (session.role == PartnerPortalRole.repUploader) return true;
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    try {
      final claims = (await user.getIdTokenResult()).claims ?? const {};
      final role = claims['role'];
      if (_staffRoles.contains(role)) return true;
      return role == 'partner' &&
          (claims['companySlug'] ?? '').toString().toLowerCase() == session.companySlug.toLowerCase() &&
          claims['portalRole'] == session.role.value &&
          _asInt(claims['credVersion'], -1) == session.credentialVersion;
    } catch (_) {
      return false;
    }
  }

  /// Signs the partner identity out and returns the browser to an anonymous
  /// session (needed by public routes). Admin sessions are handled elsewhere.
  Future<void> signOutPortalIdentity({bool restoreAnonymous = true}) async {
    final auth = _auth;
    if (auth == null) return;
    try {
      final user = auth.currentUser;
      if (user != null && !user.isAnonymous) {
        final claims = (await user.getIdTokenResult()).claims ?? const {};
        if (claims['role'] == 'partner') await auth.signOut();
      }
      if (restoreAnonymous && auth.currentUser == null) await auth.signInAnonymously();
    } catch (_) {}
  }

  static int _asInt(dynamic v, [int fallback = 1]) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);

  static String _invalidReason(PartnerPortalRole role) {
    switch (role) {
      case PartnerPortalRole.brandManager:
        return 'invalid_brand';
      case PartnerPortalRole.repUploader:
        return 'invalid_rep';
      case PartnerPortalRole.agencyOps:
        return 'invalid_agency';
    }
  }

  static bool _secretOk(String stored, String plain) => PasswordHash.passwordMatches(stored, plain).ok;

  static bool _isRepCredential(ResolvedPortalCredentials resolved, String user, String pass) {
    return resolved.repUploaderUsername.isNotEmpty &&
        user.toLowerCase() == resolved.repUploaderUsername.toLowerCase() &&
        resolved.repUploaderPasswordHash.isNotEmpty &&
        _secretOk(resolved.repUploaderPasswordHash, pass);
  }

  static PortalAuthResult _failure(String reason) {
    final msg = _serverReasonMessages[reason] ?? _serverReasonMessages['invalid_rep']!;
    return PortalAuthResult.failure(errorMessageAr: msg[0], errorMessageEn: msg[1]);
  }

  /// Suggested مندوب username. There is no default password.
  static String defaultRepUsername(String slug) => 'rep_${_sanitizeSlug(slug)}';

  /// Branding + credential versions from the server (no secrets). Used when the
  /// caller cannot read `companies/*` (everyone except admins).
  Future<ResolvedPortalCredentials> _resolveViaServer({
    required String companySlug,
    String? eventId,
    String companyNameHint = '',
  }) async {
    final res = await _functions!.httpsCallable('partnerPortalInfo').call<dynamic>({
      'companySlug': companySlug,
      if (eventId != null && eventId.trim().isNotEmpty) 'eventId': eventId.trim(),
    }).timeout(const Duration(seconds: 20));
    final m = Map<String, dynamic>.from(res.data as Map);
    return _fromServerInfo(m, companySlug: companySlug, companyNameHint: companyNameHint);
  }

  static ResolvedPortalCredentials _fromServerInfo(
    Map<String, dynamic> m, {
    String companySlug = '',
    String companyNameHint = '',
  }) {
    final slug = (m['companySlug'] ?? companySlug).toString().trim().toLowerCase();
    final name = (m['companyName'] ?? '').toString().trim();
    final hint = companyNameHint.trim();
    return ResolvedPortalCredentials(
      companySlug: slug,
      companyName: name.isNotEmpty ? name : (hint.isNotEmpty ? hint : slug.toUpperCase()),
      companyLogoUrl: (m['logoUrl'] ?? '').toString().trim(),
      brandManagerUsername: '',
      brandManagerPassword: '',
      brandCredentialVersion: _asInt(m['brandCredentialVersion']),
      agencyOpsUsername: '',
      agencyOpsPassword: '',
      agencyCredentialVersion: _asInt(m['agencyCredentialVersion']),
      eventId: m['eventId']?.toString(),
      eventName: m['eventName']?.toString(),
      hasCustomAgencyCredentials: m['hasCustomAgencyCredentials'] == true,
      customAgencyCredentialVersion: _asInt(m['customAgencyCredentialVersion']),
      repUploaderCredentialVersion: _asInt(m['repUploaderCredentialVersion']),
      repUploaderConfigured: m['repUploaderConfigured'] == true,
      serverResolved: true,
    );
  }

  static const Map<String, List<String>> _serverReasonMessages = {
    'agency_creds_on_brand': [
      'بيانات الدخول هذه مخصصة لبوابة شركة الدعاية والعمليات (/ops) ولا تملك صلاحية فتح البوابة التنفيذية للمدير العام.',
      'These credentials belong to Agency Operations (/ops) and cannot access the Brand Executive Portal.',
    ],
    'invalid_brand': [
      'اسم المستخدم أو كلمة المرور غير صحيحة للبوابة التنفيذية',
      'Invalid username or password for Brand Executive Portal',
    ],
    'brand_creds_on_agency': [
      'بيانات الدخول هذه خاصة بالبوابة التنفيذية (/portal). يرجى استخدام بيانات دخول بوابة العمليات (/ops).',
      'These are Brand Executive credentials (/portal). Please use Agency Operations (/ops) credentials.',
    ],
    'campaign_requires_custom': [
      'هذه الحملة محمية ببيانات دخول مخصصة لشركة الدعاية المسؤولة عنها.',
      'This campaign requires its dedicated campaign agency credentials.',
    ],
    'invalid_agency': [
      'اسم المستخدم أو كلمة المرور غير صحيحة لبوابة العمليات',
      'Invalid username or password for Agency Operations Portal',
    ],
    'partner_creds_on_rep': [
      'بيانات الدخول هذه لبوابة الشركة أو العمليات، وليست حساب المندوبين.',
      'These credentials belong to a company portal, not the field-rep account.',
    ],
    'rep_creds_on_partner': [
      'بيانات الدخول هذه خاصة بحساب المندوبين ولا تفتح بوابة الإدارة.',
      'These are field-rep credentials and cannot open a management portal.',
    ],
    'rep_not_configured': [
      'لم يتم إنشاء حساب المندوبين لهذه الشركة بعد.',
      'No field-rep account has been created for this company yet.',
    ],
    'invalid_rep': [
      'اسم المستخدم أو كلمة المرور غير صحيحة لحساب المندوبين',
      'Invalid username or password for the field-rep account',
    ],
    'username_required': [
      'يرجى إدخال اسم المستخدم',
      'Username is required',
    ],
    'password_required': [
      'ولّد كلمة مرور للمندوبين قبل الحفظ',
      'Generate a field-rep password before saving',
    ],
  };

  Future<PortalAuthResult> _authenticateViaServer({
    required String companySlug,
    required PartnerPortalRole requiredRole,
    required String username,
    required String password,
    required bool rememberMe,
    String? eventId,
  }) async {
    try {
      final res = await _functions!.httpsCallable('partnerPortalLogin').call<dynamic>({
        'companySlug': companySlug,
        if (eventId != null && eventId.trim().isNotEmpty) 'eventId': eventId.trim(),
        'role': requiredRole.value,
        'username': username,
        'password': password,
      }).timeout(const Duration(seconds: 20));
      final m = Map<String, dynamic>.from(res.data as Map);
      if (m['ok'] == true && m['session'] is Map) {
        final sm = Map<String, dynamic>.from(m['session'] as Map);
        final locked = sm['lockedEventId']?.toString();
        final session = PartnerPortalSession(
          companySlug: (sm['companySlug'] ?? companySlug).toString(),
          role: PartnerPortalRole.fromString(sm['role']?.toString()),
          username: (sm['username'] ?? '').toString(),
          credentialVersion: _asInt(sm['credentialVersion']),
          lockedEventId: (locked != null && locked.isNotEmpty) ? locked : null,
          isCampaignTier: sm['isCampaignTier'] == true,
          authenticatedAt: DateTime.now(),
        );
        // Rep upload keeps the anonymous Firebase user. A partner custom token
        // with partnerAccess "upload" cannot create receipts under the current
        // rules, and swapping it in would close the public upload path.
        if (requiredRole != PartnerPortalRole.repUploader) {
          final adopted = await _adoptPortalIdentity(m['customToken']?.toString());
          if (!adopted) {
            return PortalAuthResult.failure(
              errorMessageAr: 'تم التحقق من البيانات لكن تعذر فتح جلسة البوابة. حاول مرة أخرى.',
              errorMessageEn: 'Credentials verified, but the portal session could not be opened. Please try again.',
            );
          }
        }
        await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
        return PortalAuthResult.success(session);
      }
      final msg = _serverReasonMessages[m['reason']?.toString()] ??
          _serverReasonMessages[_invalidReason(requiredRole)]!;
      return PortalAuthResult.failure(errorMessageAr: msg[0], errorMessageEn: msg[1]);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return PortalAuthResult.failure(
          errorMessageAr: 'محاولات كثيرة. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.',
          errorMessageEn: 'Too many attempts. Please wait and try again.',
        );
      }
      return PortalAuthResult.failure(
        errorMessageAr: 'تعذر الاتصال بخادم التحقق. حاول مرة أخرى.',
        errorMessageEn: 'Could not reach the verification server. Please try again.',
      );
    } catch (_) {
      return PortalAuthResult.failure(
        errorMessageAr: 'تعذر الاتصال بخادم التحقق. حاول مرة أخرى.',
        errorMessageEn: 'Could not reach the verification server. Please try again.',
      );
    }
  }

  static const String _prefsKeyPrefix = 'tashil_portal_auth_v2_';

  /// Deterministic default Tier-1 Brand Manager username for a company code/slug.
  static String defaultBrandUsername(String slug) {
    final clean = _sanitizeSlug(slug);
    return 'brand_$clean';
  }

  /// Deterministic default Tier-1 Brand Manager password for a company code/slug.
  static String defaultBrandPassword(String slug) {
    final clean = _sanitizeSlug(slug);
    final hash = _deterministicPin(clean, salt: 'BM2026');
    return 'Bm#$clean$hash';
  }

  /// Deterministic default Tier-1 Agency Operations username for a company code/slug.
  static String defaultAgencyUsername(String slug) {
    final clean = _sanitizeSlug(slug);
    return 'ops_$clean';
  }

  /// Deterministic default Tier-1 Agency Operations password for a company code/slug.
  static String defaultAgencyPassword(String slug) {
    final clean = _sanitizeSlug(slug);
    final hash = _deterministicPin(clean, salt: 'OPS2026');
    return 'Op#$clean$hash';
  }

  /// Deterministic default Tier-2 Campaign Custom Agency username.
  static String defaultCampaignAgencyUsername(String slug, String eventId) {
    final cleanSlug = _sanitizeSlug(slug);
    final shortEvent = eventId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    final suffix = shortEvent.length >= 4 ? shortEvent.substring(0, 4) : (shortEvent.isEmpty ? 'camp' : shortEvent);
    return 'ops_${cleanSlug}_$suffix';
  }

  /// Deterministic default Tier-2 Campaign Custom Agency password.
  static String defaultCampaignAgencyPassword(String slug, String eventId) {
    final cleanSlug = _sanitizeSlug(slug);
    final hash = _deterministicPin('$cleanSlug:$eventId', salt: 'CAMP2026');
    return 'Cp#$cleanSlug$hash';
  }

  /// Generates a fresh random strong password (used when Admin clicks "Regenerate Password").
  static String generateRandomPassword({String prefix = 'Tg'}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rnd = Random.secure();
    final part = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$prefix#$part';
  }

  static String _sanitizeSlug(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    return cleaned.isEmpty ? 'partner' : cleaned;
  }

  static String _deterministicPin(String input, {required String salt}) {
    int h = 2166136261;
    final combined = '$salt:$input';
    for (int i = 0; i < combined.length; i++) {
      h ^= combined.codeUnitAt(i);
      h = (h * 16777619) & 0x7FFFFFFF;
    }
    final pin = (h % 9000) + 1000;
    return pin.toString();
  }

  static String _sessionStorageKey({
    required String companySlug,
    required PartnerPortalRole role,
    String? eventId,
  }) {
    final cleanSlug = _sanitizeSlug(companySlug);
    if (role == PartnerPortalRole.agencyOps && eventId != null && eventId.trim().isNotEmpty) {
      return '$_prefsKeyPrefix${role.value}_${cleanSlug}_${eventId.trim()}';
    }
    return '$_prefsKeyPrefix${role.value}_$cleanSlug';
  }

  /// Resolves Tier 1 (Company) and Tier 2 (Optional Campaign Override) credentials from Firestore,
  /// seamlessly falling back to deterministic company defaults if not yet customized.
  Future<ResolvedPortalCredentials> resolveCredentials({
    required String companySlug,
    String? companyNameHint,
    String? eventId,
  }) async {
    String resolvedSlug = companySlug.trim().toLowerCase();
    String resolvedCompanyName = companyNameHint?.trim() ?? '';

    Map<String, dynamic>? eventData;
    String? resolvedEventId = (eventId != null && eventId.trim().isNotEmpty) ? eventId.trim() : null;
    String? resolvedEventName;

    final firestore = _firestore;
    if (firestore != null) {
      if (resolvedEventId != null) {
        try {
          final eventDoc = await firestore.collection('events').doc(resolvedEventId).get();
          if (eventDoc.exists) {
            eventData = eventDoc.data();
            resolvedEventName = eventData?['eventName']?.toString();
            if (resolvedSlug.isEmpty) {
              resolvedSlug = (eventData?['companySlug'] ?? '').toString().trim().toLowerCase();
            }
            if (resolvedCompanyName.isEmpty) {
              resolvedCompanyName = (eventData?['targetCompany'] ?? '').toString().trim();
            }
          }
        } catch (_) {}
      }

      Map<String, dynamic>? companyData;
      bool companyReadFailed = false;
      if (resolvedSlug.isNotEmpty) {
        try {
          final companyDoc = await firestore.collection('companies').doc(resolvedSlug).get();
          if (companyDoc.exists) {
            companyData = companyDoc.data();
            if (resolvedCompanyName.isEmpty) {
              resolvedCompanyName = (companyData?['name'] ?? '').toString().trim();
            }
          }
        } catch (_) {
          companyReadFailed = true;
        }
      }

      // Non-admin visitors cannot read companies/* (credentials live there).
      // Never fall back to default credentials in that case: ask the server
      // for branding + versions instead. Errors propagate to the caller.
      if (_functions != null && (companyReadFailed || (resolvedSlug.isEmpty && resolvedEventId != null))) {
        return _resolveViaServer(
          companySlug: resolvedSlug,
          eventId: resolvedEventId,
          companyNameHint: companyNameHint ?? '',
        );
      }

      // If company name is still empty, check any event with this companySlug
      if (resolvedCompanyName.isEmpty && resolvedSlug.isNotEmpty) {
        try {
          final q = await firestore
              .collection('events')
              .where('companySlug', isEqualTo: resolvedSlug)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final d = q.docs.first.data();
            resolvedCompanyName = (d['targetCompany'] ?? '').toString().trim();
          }
        } catch (_) {}
      }

      final brandUser = (companyData?['brandManagerUsername'] ?? '').toString().trim();
      final brandPass = (companyData?['brandManagerPassword'] ?? '').toString().trim();
      final brandVer = (companyData?['brandCredentialVersion'] as num?)?.toInt() ?? 1;

      final agencyUser = (companyData?['agencyOpsUsername'] ?? '').toString().trim();
      final agencyPass = (companyData?['agencyOpsPassword'] ?? '').toString().trim();
      final agencyVer = (companyData?['agencyCredentialVersion'] as num?)?.toInt() ?? 1;

      final hasCustomAgency = eventData?['hasCustomAgencyCredentials'] == true;
      final customAgencyUser = (eventData?['customAgencyUsername'] ?? '').toString().trim();
      final customAgencyPass = (eventData?['customAgencyPassword'] ?? '').toString().trim();
      final customAgencyVer = (eventData?['customAgencyCredentialVersion'] as num?)?.toInt() ?? 1;
      final repUser = (companyData?['repUploaderUsername'] ?? '').toString().trim();
      final repHash = (companyData?['repUploaderPasswordHash'] ?? '').toString().trim();
      final repVer = (companyData?['repUploaderCredentialVersion'] as num?)?.toInt() ?? 1;

      return ResolvedPortalCredentials(
        companySlug: resolvedSlug,
        companyName: resolvedCompanyName.isNotEmpty ? resolvedCompanyName : resolvedSlug.toUpperCase(),
        brandManagerUsername: brandUser.isNotEmpty ? brandUser : defaultBrandUsername(resolvedSlug),
        brandManagerPassword: brandPass.isNotEmpty ? brandPass : defaultBrandPassword(resolvedSlug),
        brandCredentialVersion: brandVer,
        agencyOpsUsername: agencyUser.isNotEmpty ? agencyUser : defaultAgencyUsername(resolvedSlug),
        agencyOpsPassword: agencyPass.isNotEmpty ? agencyPass : defaultAgencyPassword(resolvedSlug),
        agencyCredentialVersion: agencyVer,
        eventId: resolvedEventId,
        eventName: resolvedEventName,
        hasCustomAgencyCredentials: hasCustomAgency,
        customAgencyUsername: customAgencyUser.isNotEmpty
            ? customAgencyUser
            : (resolvedEventId != null ? defaultCampaignAgencyUsername(resolvedSlug, resolvedEventId) : ''),
        customAgencyPassword: customAgencyPass.isNotEmpty
            ? customAgencyPass
            : (resolvedEventId != null ? defaultCampaignAgencyPassword(resolvedSlug, resolvedEventId) : ''),
        customAgencyCredentialVersion: customAgencyVer,
        repUploaderUsername: repUser,
        repUploaderPasswordHash: repHash,
        repUploaderCredentialVersion: repVer,
        repUploaderConfigured: repUser.isNotEmpty && repHash.isNotEmpty,
        companyLogoUrl: () {
          final l = (companyData?['logoUrl'] ?? '').toString().trim();
          return l.startsWith('https://') ? l : '';
        }(),
      );
    }

    final memEvent = resolvedEventId != null ? _memoryEventOverrides[resolvedEventId] : null;
    if (resolvedSlug.isEmpty && memEvent != null) {
      resolvedSlug = (memEvent['companySlug'] ?? '').toString().trim().toLowerCase();
    }
    final memCompany = _memoryCompanyCredentials[resolvedSlug];
    if (memCompany != null || memEvent != null) {
      final brandUser = (memCompany?['brandManagerUsername'] ?? '').toString().trim();
      final brandPass = (memCompany?['brandManagerPassword'] ?? '').toString().trim();
      final brandVer = (memCompany?['brandCredentialVersion'] as num?)?.toInt() ?? 1;
      final agencyUser = (memCompany?['agencyOpsUsername'] ?? '').toString().trim();
      final agencyPass = (memCompany?['agencyOpsPassword'] ?? '').toString().trim();
      final agencyVer = (memCompany?['agencyCredentialVersion'] as num?)?.toInt() ?? 1;
      final hasCustomAgency = memEvent?['hasCustomAgencyCredentials'] == true;
      final customAgencyUser = (memEvent?['customAgencyUsername'] ?? '').toString().trim();
      final customAgencyPass = (memEvent?['customAgencyPassword'] ?? '').toString().trim();
      final customAgencyVer = (memEvent?['customAgencyCredentialVersion'] as num?)?.toInt() ?? 1;
      final memCompanyName = (memCompany?['name'] ?? '').toString().trim();
      final repUser = (memCompany?['repUploaderUsername'] ?? '').toString().trim();
      final repHash = (memCompany?['repUploaderPasswordHash'] ?? '').toString().trim();
      final repVer = (memCompany?['repUploaderCredentialVersion'] as num?)?.toInt() ?? 1;
      final repConfigured = memCompany?['repUploaderConfigured'] == true || (repUser.isNotEmpty && repHash.isNotEmpty);

      return ResolvedPortalCredentials(
        companySlug: resolvedSlug,
        companyName: resolvedCompanyName.isNotEmpty
            ? resolvedCompanyName
            : (memCompanyName.isNotEmpty ? memCompanyName : resolvedSlug.toUpperCase()),
        brandManagerUsername: brandUser.isNotEmpty ? brandUser : defaultBrandUsername(resolvedSlug),
        brandManagerPassword: brandPass.isNotEmpty ? brandPass : defaultBrandPassword(resolvedSlug),
        brandCredentialVersion: brandVer,
        agencyOpsUsername: agencyUser.isNotEmpty ? agencyUser : defaultAgencyUsername(resolvedSlug),
        agencyOpsPassword: agencyPass.isNotEmpty ? agencyPass : defaultAgencyPassword(resolvedSlug),
        agencyCredentialVersion: agencyVer,
        eventId: resolvedEventId,
        eventName: resolvedEventName,
        hasCustomAgencyCredentials: hasCustomAgency,
        customAgencyUsername: customAgencyUser.isNotEmpty
            ? customAgencyUser
            : (resolvedEventId != null ? defaultCampaignAgencyUsername(resolvedSlug, resolvedEventId) : ''),
        customAgencyPassword: customAgencyPass.isNotEmpty
            ? customAgencyPass
            : (resolvedEventId != null ? defaultCampaignAgencyPassword(resolvedSlug, resolvedEventId) : ''),
        customAgencyCredentialVersion: customAgencyVer,
        repUploaderUsername: repUser,
        repUploaderPasswordHash: repHash,
        repUploaderCredentialVersion: repVer,
        repUploaderConfigured: repConfigured,
      );
    }

    return ResolvedPortalCredentials(
      companySlug: resolvedSlug,
      companyName: resolvedCompanyName.isNotEmpty ? resolvedCompanyName : resolvedSlug.toUpperCase(),
      brandManagerUsername: defaultBrandUsername(resolvedSlug),
      brandManagerPassword: defaultBrandPassword(resolvedSlug),
      brandCredentialVersion: 1,
      agencyOpsUsername: defaultAgencyUsername(resolvedSlug),
      agencyOpsPassword: defaultAgencyPassword(resolvedSlug),
      agencyCredentialVersion: 1,
      eventId: resolvedEventId,
      eventName: resolvedEventName,
      hasCustomAgencyCredentials: false,
      customAgencyUsername:
          resolvedEventId != null ? defaultCampaignAgencyUsername(resolvedSlug, resolvedEventId) : '',
      customAgencyPassword:
          resolvedEventId != null ? defaultCampaignAgencyPassword(resolvedSlug, resolvedEventId) : '',
      customAgencyCredentialVersion: 1,
    );
  }

  /// Authenticates a partner login attempt with strict role isolation (`brandManager` vs `agencyOps`)
  /// and Two-Tier inheritance/override support.
  Future<PortalAuthResult> authenticate({
    required String companySlug,
    required PartnerPortalRole requiredRole,
    required String username,
    required String password,
    required bool rememberMe,
    String? eventId,
  }) async {
    final cleanUser = username.trim();
    final cleanPass = password.trim();

    if (cleanUser.isEmpty || cleanPass.isEmpty) {
      return PortalAuthResult.failure(
        errorMessageAr: 'يرجى إدخال اسم المستخدم وكلمة المرور',
        errorMessageEn: 'Please enter both username and password',
      );
    }

    if (_functions != null) {
      return _authenticateViaServer(
        companySlug: companySlug,
        requiredRole: requiredRole,
        username: cleanUser,
        password: cleanPass,
        rememberMe: rememberMe,
        eventId: eventId,
      );
    }

    final resolved = await resolveCredentials(
      companySlug: companySlug,
      eventId: eventId,
    );

    if (requiredRole == PartnerPortalRole.brandManager) {
      // Strict Role Isolation: Check if user tried entering Agency Ops credentials on Brand Manager portal
      final isAgencyCreds = (cleanUser.toLowerCase() == resolved.agencyOpsUsername.toLowerCase() &&
              _secretOk(resolved.agencyOpsPassword, cleanPass)) ||
          (resolved.hasCustomAgencyCredentials &&
              cleanUser.toLowerCase() == resolved.customAgencyUsername.toLowerCase() &&
              _secretOk(resolved.customAgencyPassword, cleanPass));

      if (isAgencyCreds) {
        return PortalAuthResult.failure(
          errorMessageAr:
              'بيانات الدخول هذه مخصصة لبوابة شركة الدعاية والعمليات (/ops) ولا تملك صلاحية فتح البوابة التنفيذية للمدير العام.',
          errorMessageEn:
              'These credentials belong to Agency Operations (/ops) and cannot access the Brand Executive Portal.',
        );
      }

      if (_isRepCredential(resolved, cleanUser, cleanPass)) {
        return _failure('rep_creds_on_partner');
      }

      if (cleanUser.toLowerCase() == resolved.brandManagerUsername.toLowerCase() &&
          _secretOk(resolved.brandManagerPassword, cleanPass)) {
        final session = PartnerPortalSession(
          companySlug: resolved.companySlug,
          role: PartnerPortalRole.brandManager,
          username: resolved.brandManagerUsername,
          credentialVersion: resolved.brandCredentialVersion,
          authenticatedAt: DateTime.now(),
        );
        await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
        return PortalAuthResult.success(session);
      }

      return PortalAuthResult.failure(
        errorMessageAr: 'اسم المستخدم أو كلمة المرور غير صحيحة للبوابة التنفيذية',
        errorMessageEn: 'Invalid username or password for Brand Executive Portal',
      );
    }

    if (requiredRole == PartnerPortalRole.repUploader) {
      return _authenticateRepOffline(
        resolved: resolved,
        username: cleanUser,
        password: cleanPass,
        rememberMe: rememberMe,
        eventId: eventId,
      );
    }

    // requiredRole == PartnerPortalRole.agencyOps
    // Strict Role Isolation: Reject Brand Manager credentials on Agency Ops portal to enforce role separation
    if (_isRepCredential(resolved, cleanUser, cleanPass)) {
      return _failure('rep_creds_on_partner');
    }
    if (cleanUser.toLowerCase() == resolved.brandManagerUsername.toLowerCase() &&
        _secretOk(resolved.brandManagerPassword, cleanPass)) {
      return PortalAuthResult.failure(
        errorMessageAr:
            'بيانات الدخول هذه خاصة بالبوابة التنفيذية (/portal). يرجى استخدام بيانات دخول بوابة العمليات (/ops).',
        errorMessageEn:
            'These are Brand Executive credentials (/portal). Please use Agency Operations (/ops) credentials.',
      );
    }

    // Case 1: Specific campaign requested (`eventId != null`) with custom Tier-2 credentials enabled
    if (eventId != null && eventId.trim().isNotEmpty && resolved.hasCustomAgencyCredentials) {
      if (cleanUser.toLowerCase() == resolved.customAgencyUsername.toLowerCase() &&
          _secretOk(resolved.customAgencyPassword, cleanPass)) {
        final session = PartnerPortalSession(
          companySlug: resolved.companySlug,
          role: PartnerPortalRole.agencyOps,
          username: resolved.customAgencyUsername,
          credentialVersion: resolved.customAgencyCredentialVersion,
          lockedEventId: eventId.trim(),
          isCampaignTier: true,
          authenticatedAt: DateTime.now(),
        );
        await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
        return PortalAuthResult.success(session);
      }
      return PortalAuthResult.failure(
        errorMessageAr: 'هذه الحملة محمية ببيانات دخول مخصصة لشركة الدعاية المسؤولة عنها.',
        errorMessageEn: 'This campaign requires its dedicated campaign agency credentials.',
      );
    }

    // Case 2: Check if user entered Tier-2 campaign-specific credentials on the company-level `/ops/:slug` route
    if (resolved.companySlug.isNotEmpty) {
      if (_firestore != null) {
        try {
          final eventsSnap = await _firestore
              .collection('events')
              .where('companySlug', isEqualTo: resolved.companySlug)
              .get();
          for (final doc in eventsSnap.docs) {
            final data = doc.data();
            if (data['hasCustomAgencyCredentials'] == true) {
              final cUser = (data['customAgencyUsername'] ?? '').toString().trim();
              final cPass = (data['customAgencyPassword'] ?? '').toString().trim();
              final cVer = (data['customAgencyCredentialVersion'] as num?)?.toInt() ?? 1;
              final effectiveUser =
                  cUser.isNotEmpty ? cUser : defaultCampaignAgencyUsername(resolved.companySlug, doc.id);
              final effectivePass =
                  cPass.isNotEmpty ? cPass : defaultCampaignAgencyPassword(resolved.companySlug, doc.id);

              if (cleanUser.toLowerCase() == effectiveUser.toLowerCase() && _secretOk(effectivePass, cleanPass)) {
                final session = PartnerPortalSession(
                  companySlug: resolved.companySlug,
                  role: PartnerPortalRole.agencyOps,
                  username: effectiveUser,
                  credentialVersion: cVer,
                  lockedEventId: doc.id,
                  isCampaignTier: true,
                  authenticatedAt: DateTime.now(),
                );
                await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
                return PortalAuthResult.success(session);
              }
            }
          }
        } catch (_) {}
      }

      // Also check in-memory campaign overrides (for instant local updates and offline/unit tests)
      for (final entry in _memoryEventOverrides.entries) {
        final data = entry.value;
        final overrideSlug = (data['companySlug'] ?? '').toString().trim().toLowerCase();
        if ((overrideSlug.isEmpty || overrideSlug == resolved.companySlug.toLowerCase()) &&
            data['hasCustomAgencyCredentials'] == true) {
          final cUser = (data['customAgencyUsername'] ?? '').toString().trim();
          final cPass = (data['customAgencyPassword'] ?? '').toString().trim();
          final cVer = (data['customAgencyCredentialVersion'] as num?)?.toInt() ?? 1;
          final effectiveUser =
              cUser.isNotEmpty ? cUser : defaultCampaignAgencyUsername(resolved.companySlug, entry.key);
          final effectivePass =
              cPass.isNotEmpty ? cPass : defaultCampaignAgencyPassword(resolved.companySlug, entry.key);

          if (cleanUser.toLowerCase() == effectiveUser.toLowerCase() && _secretOk(effectivePass, cleanPass)) {
            final session = PartnerPortalSession(
              companySlug: resolved.companySlug,
              role: PartnerPortalRole.agencyOps,
              username: effectiveUser,
              credentialVersion: cVer,
              lockedEventId: entry.key,
              isCampaignTier: true,
              authenticatedAt: DateTime.now(),
            );
            await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
            return PortalAuthResult.success(session);
          }
        }
      }
    }

    // Case 3: Tier-1 Company-Level Agency Operations credentials
    if (cleanUser.toLowerCase() == resolved.agencyOpsUsername.toLowerCase() &&
        _secretOk(resolved.agencyOpsPassword, cleanPass)) {
      final session = PartnerPortalSession(
        companySlug: resolved.companySlug,
        role: PartnerPortalRole.agencyOps,
        username: resolved.agencyOpsUsername,
        credentialVersion: resolved.agencyCredentialVersion,
        lockedEventId: eventId?.trim(),
        isCampaignTier: false,
        authenticatedAt: DateTime.now(),
      );
      await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
      return PortalAuthResult.success(session);
    }

    return PortalAuthResult.failure(
      errorMessageAr: 'اسم المستخدم أو كلمة المرور غير صحيحة لبوابة العمليات',
      errorMessageEn: 'Invalid username or password for Agency Operations Portal',
    );
  }

  Future<PortalAuthResult> _authenticateRepOffline({
    required ResolvedPortalCredentials resolved,
    required String username,
    required String password,
    required bool rememberMe,
    String? eventId,
  }) async {
    final brandHit = username.toLowerCase() == resolved.brandManagerUsername.toLowerCase() &&
        _secretOk(resolved.brandManagerPassword, password);
    final agencyHit = username.toLowerCase() == resolved.agencyOpsUsername.toLowerCase() &&
        _secretOk(resolved.agencyOpsPassword, password);
    var campaignHit = false;
    if (resolved.hasCustomAgencyCredentials &&
        username.toLowerCase() == resolved.customAgencyUsername.toLowerCase() &&
        _secretOk(resolved.customAgencyPassword, password)) {
      campaignHit = true;
    }
    for (final entry in _memoryEventOverrides.entries) {
      final data = entry.value;
      if (data['hasCustomAgencyCredentials'] != true) continue;
      final overrideSlug = (data['companySlug'] ?? '').toString().trim().toLowerCase();
      if (overrideSlug.isNotEmpty && overrideSlug != resolved.companySlug.toLowerCase()) continue;
      final cUser = (data['customAgencyUsername'] ?? '').toString().trim();
      final cPass = (data['customAgencyPassword'] ?? '').toString().trim();
      final effectiveUser = cUser.isNotEmpty ? cUser : defaultCampaignAgencyUsername(resolved.companySlug, entry.key);
      final effectivePass = cPass.isNotEmpty ? cPass : defaultCampaignAgencyPassword(resolved.companySlug, entry.key);
      if (username.toLowerCase() == effectiveUser.toLowerCase() && _secretOk(effectivePass, password)) {
        campaignHit = true;
      }
    }
    if (brandHit || agencyHit || campaignHit) return _failure('partner_creds_on_rep');
    if (!resolved.repUploaderConfigured || resolved.repUploaderPasswordHash.isEmpty) {
      return _failure('rep_not_configured');
    }
    if (username.toLowerCase() == resolved.repUploaderUsername.toLowerCase() &&
        _secretOk(resolved.repUploaderPasswordHash, password)) {
      final session = PartnerPortalSession(
        companySlug: resolved.companySlug,
        role: PartnerPortalRole.repUploader,
        username: resolved.repUploaderUsername,
        credentialVersion: resolved.repUploaderCredentialVersion,
        authenticatedAt: DateTime.now(),
      );
      await _persistSession(session, rememberMe: rememberMe, eventId: eventId);
      return PortalAuthResult.success(session);
    }
    return _failure('invalid_rep');
  }

  Future<void> _persistSession(
    PartnerPortalSession session, {
    required bool rememberMe,
    String? eventId,
  }) async {
    final key = _sessionStorageKey(
      companySlug: session.companySlug,
      role: session.role,
      eventId: eventId,
    );
    _memorySessions[key] = session;

    final companyKey = _sessionStorageKey(
      companySlug: session.companySlug,
      role: session.role,
    );
    // Only store under company-wide key if not locked to a specific event route, or if Tier-1 company session
    if (!session.isCampaignTier || eventId == null || eventId.trim().isEmpty) {
      _memorySessions[companyKey] = session;
    }

    if (rememberMe) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(session.toJson());
        await prefs.setString(key, encoded);
        if (!session.isCampaignTier || eventId == null || eventId.trim().isEmpty) {
          await prefs.setString(companyKey, encoded);
        }
      } catch (_) {}
    }
  }

  /// Validates an existing session (from memory or SharedPreferences) against Firestore's live `credentialVersion`.
  /// Returns `null` and clears storage if the password was rotated (`credentialVersion` mismatch) or role mismatches.
  Future<PartnerPortalSession?> getValidSession({
    required String companySlug,
    required PartnerPortalRole requiredRole,
    String? eventId,
  }) async {
    final session = await _getValidStoredSession(
      companySlug: companySlug,
      requiredRole: requiredRole,
      eventId: eventId,
    );
    if (session == null) return null;
    // Data access needs the matching Firebase identity; otherwise re-login.
    if (!await _firebaseIdentityMatches(session)) return null;
    return session;
  }

  Future<PartnerPortalSession?> _getValidStoredSession({
    required String companySlug,
    required PartnerPortalRole requiredRole,
    String? eventId,
  }) async {
    final resolved = await resolveCredentials(
      companySlug: companySlug,
      eventId: eventId,
    );

    final key = _sessionStorageKey(
      companySlug: resolved.companySlug,
      role: requiredRole,
      eventId: eventId,
    );
    final fallbackCompanyKey = _sessionStorageKey(
      companySlug: resolved.companySlug,
      role: requiredRole,
    );

    PartnerPortalSession? candidate = _memorySessions[key] ?? _memorySessions[fallbackCompanyKey];

    if (candidate == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key) ?? prefs.getString(fallbackCompanyKey);
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          candidate = PartnerPortalSession.fromJson(map);
        }
      } catch (_) {}
    }

    if (candidate == null) return null;

    // Enforce strict role isolation
    if (candidate.role != requiredRole) {
      await signOut(companySlug: resolved.companySlug, role: requiredRole, eventId: eventId);
      return null;
    }

    // Enforce company slug match
    if (candidate.companySlug.toLowerCase() != resolved.companySlug.toLowerCase()) {
      return null;
    }

    // Verify credentialVersion for instant revocation on password change
    if (requiredRole == PartnerPortalRole.brandManager) {
      if (candidate.credentialVersion != resolved.brandCredentialVersion) {
        await signOut(companySlug: resolved.companySlug, role: requiredRole, eventId: eventId);
        return null;
      }
      _memorySessions[key] = candidate;
      return candidate;
    }

    if (requiredRole == PartnerPortalRole.repUploader) {
      if (!resolved.repUploaderConfigured ||
          candidate.credentialVersion != resolved.repUploaderCredentialVersion) {
        await signOut(companySlug: resolved.companySlug, role: requiredRole, eventId: eventId);
        return null;
      }
      _memorySessions[key] = candidate;
      return candidate;
    }

    {
      // Agency Ops
      // A campaign-locked Tier-2 session must never unlock a different campaign's direct link
      if (candidate.isCampaignTier &&
          eventId != null &&
          eventId.trim().isNotEmpty &&
          candidate.lockedEventId != eventId.trim()) {
        return null;
      }

      if (eventId != null && eventId.trim().isNotEmpty && resolved.hasCustomAgencyCredentials) {
        // Must be authenticated for this specific campaign and match its custom version
        if (!candidate.isCampaignTier ||
            candidate.lockedEventId != eventId.trim() ||
            candidate.credentialVersion != resolved.customAgencyCredentialVersion) {
          await signOut(companySlug: resolved.companySlug, role: requiredRole, eventId: eventId);
          return null;
        }
        _memorySessions[key] = candidate;
        return candidate;
      }

      if (candidate.isCampaignTier && candidate.lockedEventId != null && candidate.lockedEventId!.isNotEmpty) {
        final campaignResolved = await resolveCredentials(
          companySlug: resolved.companySlug,
          eventId: candidate.lockedEventId,
        );
        if (!campaignResolved.hasCustomAgencyCredentials ||
            candidate.credentialVersion != campaignResolved.customAgencyCredentialVersion) {
          await signOut(
            companySlug: resolved.companySlug,
            role: requiredRole,
            eventId: candidate.lockedEventId,
          );
          return null;
        }
        _memorySessions[key] = candidate;
        return candidate;
      }

      // Standard Tier-1 company agency session
      if (candidate.credentialVersion != resolved.agencyCredentialVersion) {
        await signOut(companySlug: resolved.companySlug, role: requiredRole, eventId: eventId);
        return null;
      }
      _memorySessions[key] = candidate;
      return candidate;
    }
  }

  /// Signs out from the current Partner Portal session and clears persisted Remember Me token.
  Future<void> signOut({
    required String companySlug,
    required PartnerPortalRole role,
    String? eventId,
  }) async {
    String effectiveSlug = _sanitizeSlug(companySlug);
    final cleanEvent = (eventId ?? '').trim().toLowerCase();
    if (effectiveSlug.isEmpty && cleanEvent.isNotEmpty) {
      final memEvent = _memoryEventOverrides[eventId!.trim()];
      if (memEvent != null) {
        effectiveSlug = _sanitizeSlug((memEvent['companySlug'] ?? '').toString());
      }
    }

    final key = _sessionStorageKey(
      companySlug: effectiveSlug.isNotEmpty ? effectiveSlug : companySlug,
      role: role,
      eventId: eventId,
    );
    final companyKey = _sessionStorageKey(
      companySlug: effectiveSlug.isNotEmpty ? effectiveSlug : companySlug,
      role: role,
    );
    final rolePrefix = '$_prefsKeyPrefix${role.value}_';
    final targetSlug = effectiveSlug.isNotEmpty ? effectiveSlug : _sanitizeSlug(companySlug);
    final rawSlug = _sanitizeSlug(companySlug);
    final eventSuffix = cleanEvent.isNotEmpty ? '_$cleanEvent' : null;

    _memorySessions.remove(key);
    _memorySessions.remove(companyKey);
    _memorySessions.removeWhere((k, _) {
      if (!k.startsWith(_prefsKeyPrefix)) return false;
      if (k == key || k == companyKey) return true;
      if (k.startsWith(rolePrefix)) {
        if (targetSlug.isNotEmpty && (k.contains('_$targetSlug') || k.contains(targetSlug))) return true;
        if (rawSlug.isNotEmpty && (k.contains('_$rawSlug') || k.contains(rawSlug))) return true;
        if (eventSuffix != null && k.endsWith(eventSuffix)) return true;
      }
      return false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove(companyKey);
      final keysToRemove = prefs.getKeys().where((k) {
        if (!k.startsWith(_prefsKeyPrefix)) return false;
        if (k == key || k == companyKey) return true;
        if (k.startsWith(rolePrefix)) {
          if (targetSlug.isNotEmpty && (k.contains('_$targetSlug') || k.contains(targetSlug))) return true;
          if (rawSlug.isNotEmpty && (k.contains('_$rawSlug') || k.contains(rawSlug))) return true;
          if (eventSuffix != null && k.endsWith(eventSuffix)) return true;
        }
        return false;
      }).toList();
      for (final k in keysToRemove) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// Exhaustively clears all stored sessions for a company across all roles and events.
  Future<void> signOutAllRoles({
    required String companySlug,
    String? eventId,
  }) async {
    for (final role in PartnerPortalRole.values) {
      await signOut(companySlug: companySlug, role: role, eventId: eventId);
      await signOut(companySlug: companySlug, role: role, eventId: null);
    }
  }

  /// Saves updated Tier-1 Company Credentials to Firestore and increments `credentialVersion` when password changes.
  Future<ResolvedPortalCredentials> saveCompanyCredentials({
    required String companySlug,
    required String companyName,
    required String brandManagerUsername,
    required String brandManagerPassword,
    required String agencyOpsUsername,
    required String agencyOpsPassword,
    bool incrementBrandVersion = false,
    bool incrementAgencyVersion = false,
  }) async {
    final current = await resolveCredentials(
      companySlug: companySlug,
      companyNameHint: companyName,
    );

    final brandInput = brandManagerPassword.trim();
    final agencyInput = agencyOpsPassword.trim();
    // Empty means "keep the stored secret". Prevents a masked admin field
    // from wiping a password or rewriting a hash back to plaintext.
    final brandPassChanged = incrementBrandVersion ||
        (brandInput.isNotEmpty && brandInput != current.brandManagerPassword);
    final agencyPassChanged = incrementAgencyVersion ||
        (agencyInput.isNotEmpty && agencyInput != current.agencyOpsPassword);
    final brandToKeep = brandInput.isNotEmpty ? brandInput : current.brandManagerPassword;
    final agencyToKeep = agencyInput.isNotEmpty ? agencyInput : current.agencyOpsPassword;

    final newBrandVersion =
        brandPassChanged ? current.brandCredentialVersion + 1 : current.brandCredentialVersion;
    final newAgencyVersion =
        agencyPassChanged ? current.agencyCredentialVersion + 1 : current.agencyCredentialVersion;

    final cleanSlug = _sanitizeSlug(companySlug);
    if (cleanSlug.isNotEmpty) {
      _memoryCompanyCredentials[cleanSlug] = {
        ...(_memoryCompanyCredentials[cleanSlug] ?? const <String, dynamic>{}),
        'slug': cleanSlug,
        if (companyName.trim().isNotEmpty) 'name': companyName.trim(),
        'brandManagerUsername': brandManagerUsername.trim(),
        'brandManagerPassword': brandToKeep,
        'brandCredentialVersion': newBrandVersion,
        'agencyOpsUsername': agencyOpsUsername.trim(),
        'agencyOpsPassword': agencyToKeep,
        'agencyCredentialVersion': newAgencyVersion,
      };
    }
    if (_firestore != null && cleanSlug.isNotEmpty) {
      await _firestore.collection('companies').doc(cleanSlug).set({
        'slug': cleanSlug,
        if (companyName.trim().isNotEmpty) 'name': companyName.trim(),
        'brandManagerUsername': brandManagerUsername.trim(),
        if (brandInput.isNotEmpty) 'brandManagerPassword': brandInput,
        'brandCredentialVersion': newBrandVersion,
        'agencyOpsUsername': agencyOpsUsername.trim(),
        if (agencyInput.isNotEmpty) 'agencyOpsPassword': agencyInput,
        'agencyCredentialVersion': newAgencyVersion,
        'credentialsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return ResolvedPortalCredentials(
      companySlug: cleanSlug,
      companyName: companyName.trim().isNotEmpty ? companyName.trim() : current.companyName,
      brandManagerUsername: brandManagerUsername.trim(),
      brandManagerPassword: brandToKeep,
      brandCredentialVersion: newBrandVersion,
      agencyOpsUsername: agencyOpsUsername.trim(),
      agencyOpsPassword: agencyToKeep,
      agencyCredentialVersion: newAgencyVersion,
      repUploaderUsername: current.repUploaderUsername,
      repUploaderPasswordHash: current.repUploaderPasswordHash,
      repUploaderCredentialVersion: current.repUploaderCredentialVersion,
      repUploaderConfigured: current.repUploaderConfigured,
      eventId: current.eventId,
      eventName: current.eventName,
      hasCustomAgencyCredentials: current.hasCustomAgencyCredentials,
      customAgencyUsername: current.customAgencyUsername,
      customAgencyPassword: current.customAgencyPassword,
      customAgencyCredentialVersion: current.customAgencyCredentialVersion,
    );
  }

  /// Saves updated Tier-2 Campaign Custom Agency Override to Firestore and increments version when password changes.
  Future<int> saveCampaignAgencyOverride({
    required String eventId,
    required String companySlug,
    required bool hasCustomAgencyCredentials,
    required String customAgencyUsername,
    required String customAgencyPassword,
    bool forceIncrementVersion = false,
  }) async {
    if (eventId.trim().isEmpty) return 1;

    final current = await resolveCredentials(companySlug: companySlug, eventId: eventId);
    final passInput = customAgencyPassword.trim();
    final passChanged = forceIncrementVersion ||
        hasCustomAgencyCredentials != current.hasCustomAgencyCredentials ||
        (passInput.isNotEmpty && passInput != current.customAgencyPassword);
    final nextVersion = passChanged
        ? current.customAgencyCredentialVersion + 1
        : current.customAgencyCredentialVersion;
    final passToKeep = passInput.isNotEmpty ? passInput : current.customAgencyPassword;

    _memoryEventOverrides[eventId.trim()] = {
      'companySlug': _sanitizeSlug(companySlug),
      'hasCustomAgencyCredentials': hasCustomAgencyCredentials,
      'customAgencyUsername': customAgencyUsername.trim(),
      'customAgencyPassword': passToKeep,
      'customAgencyCredentialVersion': nextVersion,
    };

    if (_firestore != null) {
      await _firestore.collection('events').doc(eventId.trim()).update({
        'hasCustomAgencyCredentials': hasCustomAgencyCredentials,
        'customAgencyUsername': customAgencyUsername.trim(),
        if (passInput.isNotEmpty) 'customAgencyPassword': passInput,
        'customAgencyCredentialVersion': nextVersion,
      });
    }
    return nextVersion;
  }

  /// Creates or rotates the shared مندوب account for one company.
  /// The returned credentials never include the password. A new password is
  /// hashed before it is stored. Empty [password] keeps the current hash.
  Future<PortalAuthResult> saveRepUploaderCredentials({
    required String companySlug,
    required String username,
    String password = '',
    String companyName = '',
  }) async {
    final cleanSlug = _sanitizeSlug(companySlug);
    final user = username.trim();
    final pass = password.trim();
    if (cleanSlug.isEmpty) {
      return _failure('username_required');
    }
    if (user.isEmpty) return _failure('username_required');

    if (_functions != null) {
      try {
        final res = await _functions.httpsCallable('partnerPortalSetRepCredentials').call<dynamic>({
          'companySlug': cleanSlug,
          'username': user,
          if (pass.isNotEmpty) 'password': pass,
        }).timeout(const Duration(seconds: 20));
        final m = Map<String, dynamic>.from(res.data as Map);
        final version = _asInt(m['credentialVersion']);
        final savedUser = (m['username'] ?? user).toString();
        _memoryCompanyCredentials[cleanSlug] = {
          ...(_memoryCompanyCredentials[cleanSlug] ?? const <String, dynamic>{}),
          'slug': cleanSlug,
          if (companyName.trim().isNotEmpty) 'name': companyName.trim(),
          'repUploaderUsername': savedUser,
          'repUploaderPasswordHash': '',
          'repUploaderCredentialVersion': version,
          'repUploaderConfigured': true,
        };
        return PortalAuthResult.success(PartnerPortalSession(
          companySlug: cleanSlug,
          role: PartnerPortalRole.repUploader,
          username: savedUser,
          credentialVersion: version,
          authenticatedAt: DateTime.now(),
        ));
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'permission-denied') {
          return PortalAuthResult.failure(
            errorMessageAr: 'حفظ حساب المندوبين متاح لمدير النظام فقط.',
            errorMessageEn: 'Only an admin can save the field-rep account.',
          );
        }
        if (e.code == 'failed-precondition') return _failure('password_required');
        return PortalAuthResult.failure(
          errorMessageAr: 'تعذر حفظ حساب المندوبين. حاول مرة أخرى.',
          errorMessageEn: 'Could not save the field-rep account. Please try again.',
        );
      } catch (_) {
        return PortalAuthResult.failure(
          errorMessageAr: 'تعذر حفظ حساب المندوبين. حاول مرة أخرى.',
          errorMessageEn: 'Could not save the field-rep account. Please try again.',
        );
      }
    }

    final current = await resolveCredentials(
      companySlug: cleanSlug,
      companyNameHint: companyName,
    );
    if (pass.isEmpty && current.repUploaderPasswordHash.isEmpty) {
      return _failure('password_required');
    }
    final initial = current.repUploaderUsername.isEmpty && current.repUploaderPasswordHash.isEmpty;
    final userChanged = user.toLowerCase() != current.repUploaderUsername.toLowerCase();
    final passChanged = pass.isNotEmpty;
    final nextVersion = initial
        ? 1
        : ((userChanged || passChanged)
            ? current.repUploaderCredentialVersion + 1
            : current.repUploaderCredentialVersion);
    // Offline/tests only. Production hashing happens inside the callable.
    final hash = passChanged ? PasswordHash.hash(pass, iterations: 1000) : current.repUploaderPasswordHash;
    _memoryCompanyCredentials[cleanSlug] = {
      ...(_memoryCompanyCredentials[cleanSlug] ?? const <String, dynamic>{}),
      'slug': cleanSlug,
      if (companyName.trim().isNotEmpty) 'name': companyName.trim(),
      'repUploaderUsername': user,
      'repUploaderPasswordHash': hash,
      'repUploaderCredentialVersion': nextVersion,
      'repUploaderConfigured': true,
    };
    if (_firestore != null) {
      await _firestore.collection('companies').doc(cleanSlug).set({
        'slug': cleanSlug,
        if (companyName.trim().isNotEmpty) 'name': companyName.trim(),
        'repUploaderUsername': user,
        'repUploaderPasswordHash': hash,
        'repUploaderCredentialVersion': nextVersion,
        'repCredentialsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
    }
    return PortalAuthResult.success(PartnerPortalSession(
      companySlug: cleanSlug,
      role: PartnerPortalRole.repUploader,
      username: user,
      credentialVersion: nextVersion,
      authenticatedAt: DateTime.now(),
    ));
  }

  /// Formats a ready-to-share 1-Click WhatsApp Login Card.
  static String buildWhatsAppLoginCard({
    required PartnerPortalRole role,
    required String companyName,
    required String portalUrl,
    required String username,
    required String password,
    String? campaignName,
    bool isCustomCampaignTier = false,
    bool isAr = true,
  }) {
    final sharePassword = PasswordHash.isHash(password) ? '' : password;
    final passwordLineAr = sharePassword.isEmpty
        ? '🔑 *كلمة المرور:* محفوظة بشكل مشفّر ولن تُعرض. ولّد كلمة جديدة من لوحة الإدارة إذا أردت مشاركتها.'
        : '🔑 *كلمة المرور:* `$sharePassword`';
    final passwordLineEn = sharePassword.isEmpty
        ? '🔑 *Password:* stored as a hash and hidden. Generate a new one in admin if you need to share it.'
        : '🔑 *Password:* `$sharePassword`';
    if (isAr) {
      final roleTitle = switch (role) {
        PartnerPortalRole.brandManager =>
          '📊 البوابة التنفيذية لمدير العلامة التجارية (Brand Executive Portal)',
        PartnerPortalRole.repUploader => '🧾 تطبيق المندوب — رفع الفواتير',
        PartnerPortalRole.agencyOps => isCustomCampaignTier && campaignName != null && campaignName.isNotEmpty
            ? '🏪 بوابة شركة الدعاية والعمليات الميدانية — حملة ($campaignName)'
            : '🏪 بوابة شركة الدعاية والعمليات الميدانية (Agency Operations Portal)',
      };
      final permissionsNote = switch (role) {
        PartnerPortalRole.brandManager =>
          '• متابعة مؤشرات الأداء الفورية (ROI)، المبيعات، الفواتير، وأرصدة الهدايا بالفروع (للاطلاع والتصدير).',
        PartnerPortalRole.repUploader =>
          '• تصوير الفاتورة ورفعها للحملة والفرع. لا يفتح تقارير الإدارة ولا أرصدة الهدايا.',
        PartnerPortalRole.agencyOps =>
          '• إدارة وتوزيع أرصدة الهدايا بالفروع، التسويات، ومتابعة الفواتير الميدانية لحظياً.',
      };

      return '''🔐 *بطاقة الدخول الذكية — $companyName*
$roleTitle

🌐 *رابط الدخول المباشر:*
$portalUrl

👤 *اسم المستخدم:* `$username`
$passwordLineAr`

✨ *الصلاحيات المتاحة:*
$permissionsNote
💡 *ملاحظة:* يمكنك تفعيل خيار *"تذكرني على هذا الجهاز"* عند أول تسجيل دخول لفتح البوابة مستقبلاً بضغطة واحدة دون إعادة كتابة كلمة المرور.''';
    } else {
      final roleTitle = switch (role) {
        PartnerPortalRole.brandManager => '📊 Brand Executive Portal',
        PartnerPortalRole.repUploader => '🧾 Field rep app — receipt upload',
        PartnerPortalRole.agencyOps => isCustomCampaignTier && campaignName != null && campaignName.isNotEmpty
            ? '🏪 Agency Operations Portal — Campaign ($campaignName)'
            : '🏪 Agency Operations Portal',
      };
      final permissionsNote = switch (role) {
        PartnerPortalRole.brandManager =>
          '• Live ROI analytics, sales metrics, receipt logs, and read-only branch gift stock balances.',
        PartnerPortalRole.repUploader =>
          '• Photograph and upload receipts for a campaign and branch. No admin reports or stock editing.',
        PartnerPortalRole.agencyOps =>
          '• Full branch gift stock management, settlements, and live field receipt operations.',
      };

      return '''🔐 *Partner Access Card — $companyName*
$roleTitle

🌐 *Direct Portal Link:*
$portalUrl

👤 *Username:* `$username`
$passwordLineEn`

✨ *Access Scope:*
$permissionsNote
💡 *Tip:* Check *"Remember me on this device"* on your first login for instant 1-click access next time.''';
    }
  }
}
