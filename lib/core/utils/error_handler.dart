import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// AppErrorHandler provides centralized, user-friendly Arabic error messaging
/// tailored for an Online-Only (أونلاين فقط) system architecture.
class AppErrorHandler {
  /// Converts any error/exception into a clear, actionable Arabic message.
  static String getFriendlyMessage(dynamic error, {String? defaultMessage}) {
    if (error == null) return defaultMessage ?? 'حدث خطأ أثناء معالجة البيانات، يرجى المحاولة ثانية';

    final str = error.toString().toLowerCase();

    // Firebase Auth exceptions
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'اسم المستخدم أو البريد الإلكتروني غير مسجل.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'كلمة المرور غير صحيحة، يرجى التأكد والمحاولة مجدداً.';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب. يرجى التواصل مع إدارة النظام.';
        case 'invalid-email':
          return 'صيغة البريد الإلكتروني غير صالحة.';
        case 'network-request-failed':
          return 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت (النظام يعمل أونلاين فقط).';
        case 'too-many-requests':
          return 'تم حظر المحاولات مؤقتاً لكثرة الطلبات. يرجى الانتظار قليلاً والمحاولة مجدداً.';
        default:
          return error.message ?? 'فشل تسجيل الدخول (${error.code}).';
      }
    }

    // Cloud Functions: the server already sends a specific Arabic message.
    if (error is FirebaseFunctionsException) {
      final msg = (error.message ?? '').trim();
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(msg)) return msg;
    }

    // Firestore exceptions
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'تعذر الاتصال بقاعدة البيانات السحابية. يرجى التحقق من اتصال الإنترنت، حيث أن المنظومة تعمل بنظام الاتصال المباشر (Online Only).';
        case 'permission-denied':
          return 'عفواً، ليس لديك الصلاحيات الكافية لتنفيذ هذا الإجراء على قاعدة البيانات.';
        case 'not-found':
          return 'البيانات المطلوبة غير موجودة في قاعدة البيانات.';
        case 'already-exists':
          return 'هذا السجل مسجل مسبقاً في قاعدة البيانات.';
        case 'deadline-exceeded':
          return 'استغرقت العملية وقتاً أطول من المتوقع. يرجى التأكد من استقرار الإنترنت والمحاولة ثانية.';
        case 'unauthenticated':
          return 'انتهت جلسة تسجيل الدخول. يرجى إعادة تسجيل الدخول لمتابعة العمل.';
        default:
          break;
      }
    }

    // JSON / Parsing / Format errors
    if (str.contains('formatsyntaxerror') ||
        str.contains('formatexception') ||
        str.contains('expected property name') ||
        str.contains('unexpected character') ||
        str.contains('position') && str.contains('json') ||
        str.contains('syntaxerror') ||
        str.contains('malformed json')) {
      return 'تعذر قراءة بيانات الفاتورة بالذكاء الاصطناعي بشكل دقيق. يرجى التأكد من وضوح تصوير الفاتورة وإضاءتها وإعادة المحاولة.';
    }

    // AI Billing & Prepayment Credits
    if (str.contains('prepayment') ||
        str.contains('credits are depleted') ||
        str.contains('billing') ||
        str.contains('depleted')) {
      return 'رصيد حساب Google AI Studio (Gemini API) قد نفد. يرجى تجديد أو شحن رصيد الـ API Key من لوحة تحكم Google AI Studio لمتابعة فحص الفواتير.';
    }

    // AI Quota / Rate limit errors
    if (str.contains('quota') ||
        str.contains('resource_exhausted') ||
        str.contains('rate limit') ||
        str.contains('429') ||
        str.contains('generativeaiexception') ||
        str.contains('gemini api error')) {
      return 'خدمة التحليل بالذكاء الاصطناعي مشغولة حالياً بكثرة الطلبات. يرجى الانتظار ثوانٍ معدودة والمحاولة مرة أخرى.';
    }

    // AI proxy (geminiGenerate) failures: client-side request errors or
    // server-side function errors. Show a clear AI-service message.
    if (str.contains('ai_service_error') ||
        str.contains('geminigenerate') ||
        (error is FirebaseException && error.plugin == 'firebase_functions')) {
      return 'تعذر الاتصال بخدمة التحليل بالذكاء الاصطناعي حالياً. يرجى المحاولة مرة أخرى بعد قليل، وإذا تكررت المشكلة تواصل مع الدعم الفني.';
    }

    // Timeout / Deadline
    if (str.contains('timeout') ||
        str.contains('timed out') ||
        str.contains('deadline exceeded')) {
      return 'استغرقت عملية فحص الفاتورة وقتاً أطول من المتوقع بسبب ضعف اتصال الإنترنت. يرجى المحاولة مجدداً.';
    }

    // Image / decoding issues
    if (str.contains('image') && (str.contains('decode') || str.contains('invalid') || str.contains('corrupt'))) {
      return 'صورة الفاتورة غير مقروءة أو تالفة. يرجى التقاط صورة واضحة ومستقيمة لكامل الفاتورة.';
    }

    // Network / Offline string matches
    if (str.contains('offline') ||
        str.contains('unavailable') ||
        str.contains('network') ||
        str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('connection refused') ||
        str.contains('connection closed') ||
        str.contains('client is offline')) {
      return 'تعذر الاتصال بالإنترنت أو الخادم السحابي. يرجى التأكد من اتصالك بالإنترنت، حيث تعمل المنظومة بنظام الاتصال المباشر (Online Only).';
    }

    // If the error message is already in Arabic without raw English code errors, return it cleanly
    if (error is Exception) {
      final msg = error.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '').trim();
      final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(msg);
      final hasEnglishSyntaxError = RegExp(r'[a-zA-Z]{4,}:|NoSuchMethod|Null check|at position').hasMatch(msg);
      if (hasArabic && !hasEnglishSyntaxError && msg.isNotEmpty) {
        return msg;
      }
    }

    if (defaultMessage != null && defaultMessage.isNotEmpty) {
      return defaultMessage;
    }

    return 'حدث خطأ أثناء معالجة بيانات الفاتورة. يرجى التأكد من وضوح الصورة وإعادة المحاولة.';
  }

  /// True when the claim callable says the receipt's gift was already
  /// dispensed (safe to treat a retried auto-claim as done).
  static bool isAlreadyClaimedError(dynamic error) {
    if (error is FirebaseFunctionsException) {
      final m = (error.message ?? '').toLowerCase();
      return error.code == 'failed-precondition' && m.contains('already claimed');
    }
    return error.toString().toLowerCase().contains('already claimed');
  }

  /// Reason codes the server sends in `details.reason` when it refuses a gift
  /// claim because the campaign conditions are not met. Each one rejects the
  /// claim before any stock or receipt write.
  static const Map<String, String> claimEligibilityMessages = {
    'campaign_inactive': 'الحملة غير نشطة حالياً، لا يمكن صرف هدية هذه الفاتورة.',
    'campaign_not_started': 'الحملة لم تبدأ بعد، لا يمكن صرف هدية هذه الفاتورة.',
    'campaign_ended': 'انتهت الحملة، لا يمكن صرف هدية هذه الفاتورة.',
    'receipt_date_outside_campaign':
        'تاريخ الشراء في الفاتورة خارج فترة الحملة، ولم يُصرف أي مخزون.',
    'receipt_lines_missing':
        'تعذر التحقق من شروط الحملة لأن أصناف الفاتورة غير محفوظة. يرجى إعادة رفع الفاتورة من المندوب، ولم يُصرف أي مخزون.',
    'required_products_missing':
        'الفاتورة لا تحتوي على أي من منتجات الحملة المطلوبة، ولم يُصرف أي مخزون.',
    'min_spend_not_met':
        'قيمة مشتريات منتجات الحملة في الفاتورة أقل من الحد الأدنى المطلوب، ولم يُصرف أي مخزون.',
    'no_eligible_gift':
        'الفاتورة لا تستوفي شروط أي عرض في الحملة، لذلك لا تُصرف هدية.',
  };

  /// The server's machine-readable rejection reason, or null.
  static String? claimRejectionReason(dynamic error) {
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      if (details is Map) {
        final reason = details['reason'];
        if (reason is String && reason.isNotEmpty) return reason;
      }
    }
    return null;
  }

  /// Real Arabic reason for a failed gift claim (server English messages
  /// are translated; Arabic server messages are shown as-is).
  static String claimFailureMessage(dynamic error) {
    if (error is FirebaseFunctionsException) {
      final msg = (error.message ?? '').trim();
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(msg)) return msg;
      final eligibility = claimEligibilityMessages[claimRejectionReason(error)];
      if (eligibility != null) return eligibility;
      final m = msg.toLowerCase();
      if (m.contains('already claimed')) return 'تم صرف هدية هذه الفاتورة من قبل.';
      if (m.contains('not enough prize stock')) return 'رصيد الهدايا في هذا الفرع لا يكفي. يرجى تغذية الرصيد ثم إعادة المحاولة.';
      if (m.contains('campaign is not active')) return 'الحملة غير نشطة حالياً، لا يمكن صرف الهدايا.';
      if (m.contains('campaign not found')) return 'الحملة غير موجودة.';
      if (m.contains('receipt not found')) return 'الفاتورة غير موجودة.';
      if (m.contains('your own receipt')) return 'لا يمكنك صرف هدية فاتورة سجلها مندوب آخر.';
      if (m.contains('different campaign')) return 'الفاتورة تابعة لحملة أخرى.';
      if (m.contains('cannot dispense')) return 'هذا الحساب غير مسموح له بصرف الهدايا.';
      if (m.contains('app check')) return 'فشل التحقق من التطبيق (App Check). أغلق التطبيق وافتحه ثم أعد المحاولة.';
      if (m.contains('nothing to claim')) return 'لا توجد هدية لصرفها لهذه الفاتورة.';
      if (error.code == 'unauthenticated') return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى ثم أعد المحاولة.';
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') return 'تعذر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.';
      return 'تعذر صرف الهدية (${error.code})${msg.isNotEmpty ? ': $msg' : ''}';
    }
    return getFriendlyMessage(error, defaultMessage: 'حدث خطأ أثناء صرف الهدية');
  }
}
