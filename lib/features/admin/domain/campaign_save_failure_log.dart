import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_version_config.dart';
import 'campaign_save_confirmation.dart';

/// TAG-43: records why a campaign save did not land, so a failure in the
/// admin's browser is visible without screenshots.
///
/// Always printed to the browser console. Also sent, best effort, to the
/// staff-only `save_failures` collection (admin create-only, small fixed
/// fields, see firestore.rules). The log write never blocks or fails the
/// save. If the browser's queue is the problem, the log reaches the server
/// together with the queue, or not at all; the console line is still there.
class CampaignSaveFailureLog {
  CampaignSaveFailureLog._();

  static const collection = 'save_failures';

  /// Kinds of records.
  static const kindTimeout = 'timeout'; // not confirmed after the wait
  static const kindLateSuccess = 'late_success'; // landed after the wait
  static const kindLateError = 'late_error'; // failed after the wait
  static const kindError = 'error'; // failed within the wait

  /// Fields allowed by the rules (keep in sync with firestore.rules).
  static const fields = <String>[
    'kind', 'op', 'code', 'message', 'eventId', 'companySlug', 'payloadBytes',
    'elapsedMs', 'appVersion', 'userAgent', 'uid', 'createdAt',
  ];

  /// The record for [kind]; pure so it can be tested.
  static Map<String, dynamic> record({
    required String kind,
    required bool isNew,
    required String eventId,
    required String companySlug,
    required String uid,
    required int elapsedMs,
    int payloadBytes = 0,
    CampaignSaveFailure? failure,
    String userAgent = '',
  }) {
    String clip(String s, int n) => s.length > n ? s.substring(0, n) : s;
    return <String, dynamic>{
      'kind': kind,
      'op': isNew ? 'create' : 'edit',
      'code': clip(failure?.code ?? '', 100),
      'message': clip(failure?.message ?? '', 500),
      'eventId': clip(eventId, 100),
      'companySlug': clip(companySlug, 100),
      'payloadBytes': payloadBytes,
      'elapsedMs': elapsedMs,
      'appVersion': AppVersionConfig.appVersion,
      'userAgent': clip(userAgent, 300),
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Approximate size of [data] as JSON (Timestamps and sentinels count as
  /// short strings). Used only for the log.
  static int approxBytes(Map<String, dynamic> data) {
    try {
      return utf8.encode(jsonEncode(data, toEncodable: (o) => o.toString())).length;
    } catch (_) {
      return 0;
    }
  }

  /// Prints [rec] to the console and sends it to [firestore] without
  /// waiting. Never throws.
  static void send(FirebaseFirestore firestore, Map<String, dynamic> rec) {
    final printable = Map<String, dynamic>.from(rec)..remove('createdAt');
    debugPrint('TAG-43 campaign save: ${jsonEncode(printable)}');
    try {
      final write = firestore.collection(collection).add(rec);
      unawaited(write.then((_) {}, onError: (Object e) {
        debugPrint('TAG-43 save_failures log not written: $e');
      }));
    } catch (e) {
      debugPrint('TAG-43 save_failures log not written: $e');
    }
  }
}
