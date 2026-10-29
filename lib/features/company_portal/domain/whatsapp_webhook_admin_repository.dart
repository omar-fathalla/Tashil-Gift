import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_service.dart';
import 'whatsapp_webhook_admin_models.dart';
import '../../../core/services/firebase_scope.dart';

abstract class WhatsappWebhookAdminRepository {
  Stream<WhatsappWebhookConfig> watchConfig();
  Stream<List<WhatsappInboundMessage>> watchInbox();
  Stream<List<WhatsappSenderLink>> watchLinks();
  Stream<List<WhatsappCampaignRegistration>> watchCampaigns();
  Stream<Map<String, int>> watchAckCounts();
  Future<void> updateConfig(Map<String, dynamic> data);
  Future<void> upsertLink(Map<String, dynamic> data);
  Future<void> deleteLink(String phone);
}

class FirestoreWhatsappWebhookAdminRepository implements WhatsappWebhookAdminRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirestoreWhatsappWebhookAdminRepository(this._db, this._functions);

  @override
  Stream<WhatsappWebhookConfig> watchConfig() {
    return _db.collection('whatsapp_webhook_config').doc('default').snapshots().map(
          (snap) => WhatsappWebhookConfig.fromMap(snap.data()),
        );
  }

  @override
  Stream<List<WhatsappInboundMessage>> watchInbox() {
    return _db
        .collection('whatsapp_inbound_messages')
        .orderBy('receivedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => WhatsappInboundMessage.fromDoc(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<WhatsappSenderLink>> watchLinks() {
    return _db.collection('whatsapp_sender_links').limit(300).snapshots().map(
          (snap) => snap.docs.map((doc) => WhatsappSenderLink.fromDoc(doc.id, doc.data())).toList()
            ..sort((a, b) => a.phone.compareTo(b.phone)),
        );
  }

  @override
  Stream<List<WhatsappCampaignRegistration>> watchCampaigns() {
    return _db.collection('whatsapp_webhook_campaigns').limit(200).snapshots().map(
          (snap) => snap.docs
              .map((doc) => WhatsappCampaignRegistration.fromDoc(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<Map<String, int>> watchAckCounts() {
    return _db.collection('whatsapp_message_status').limit(300).snapshots().map((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final name = (doc.data()['ackName'] ?? 'UNKNOWN').toString();
        counts[name] = (counts[name] ?? 0) + 1;
      }
      return counts;
    });
  }

  Future<void> _call(String name, Map<String, dynamic> data) {
    return _functions.httpsCallable(name).call<dynamic>(data).timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> updateConfig(Map<String, dynamic> data) {
    return _call('updateWhatsappWebhookConfig', data);
  }

  @override
  Future<void> upsertLink(Map<String, dynamic> data) {
    return _call('manageWhatsappSenderLink', {...data, 'action': 'upsert'});
  }

  @override
  Future<void> deleteLink(String phone) {
    return _call('manageWhatsappSenderLink', {'action': 'delete', 'phone': phone});
  }
}

final whatsappWebhookRepositoryProvider = Provider<WhatsappWebhookAdminRepository>((ref) {
  return FirestoreWhatsappWebhookAdminRepository(
    ref.watch(firestoreProvider),
    scopedFunctions(),
  );
});

final whatsappWebhookConfigProvider = StreamProvider<WhatsappWebhookConfig>((ref) {
  return ref.watch(whatsappWebhookRepositoryProvider).watchConfig();
});

final whatsappInboundMessagesProvider = StreamProvider<List<WhatsappInboundMessage>>((ref) {
  return ref.watch(whatsappWebhookRepositoryProvider).watchInbox();
});

final whatsappSenderLinksProvider = StreamProvider<List<WhatsappSenderLink>>((ref) {
  return ref.watch(whatsappWebhookRepositoryProvider).watchLinks();
});

final whatsappCampaignRegistrationsProvider = StreamProvider<List<WhatsappCampaignRegistration>>((ref) {
  return ref.watch(whatsappWebhookRepositoryProvider).watchCampaigns();
});

final whatsappAckCountsProvider = StreamProvider<Map<String, int>>((ref) {
  return ref.watch(whatsappWebhookRepositoryProvider).watchAckCounts();
});
