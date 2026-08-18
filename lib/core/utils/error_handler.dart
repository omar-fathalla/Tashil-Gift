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

    // AI Quota / Rate limit errors
    if (str.contains('quota') ||
        str.contains('resource_exhausted') ||
        str.contains('rate limit') ||
        str.contains('429') ||
        str.contains('generativeaiexception') ||
        str.contains('gemini api error')) {
      return 'خدمة التحليل بالذكاء الاصطناعي مشغولة حالياً بكثرة الطلبات. يرجى الانتظار ثوانٍ معدودة والمحاولة مرة أخرى.';
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
}



