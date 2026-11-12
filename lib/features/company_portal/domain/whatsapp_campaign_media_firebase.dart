import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'whatsapp_campaign_media.dart';

/// Stores campaign media in the `tashil-gift` bucket and returns a download URL
/// WAHA can fetch without the admin's browser session.
///
/// [Reference.getDownloadURL] appends an unguessable `token`. Security rules
/// still allow SDK reads only for `super_admin` and `admin`, and they deny
/// listing `whatsapp_campaign_media/`. The token stays valid for the whole
/// recipient list (it does not expire mid-send the way a short-lived signed
/// URL can).
class FirebaseWhatsAppCampaignMediaStorage
    implements WhatsAppCampaignMediaStorage {
  final FirebaseStorage storage;

  const FirebaseWhatsAppCampaignMediaStorage(this.storage);

  @override
  Future<String> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    void Function(int transferred, int total)? onProgress,
  }) async {
    final ref = storage.ref().child(storagePath);
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: customMetadata,
      ),
    );
    final subscription = task.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes > 0
          ? snapshot.totalBytes
          : bytes.length;
      onProgress?.call(snapshot.bytesTransferred, total);
    });
    try {
      await task.timeout(const Duration(seconds: 90));
    } finally {
      await subscription.cancel();
    }
    return ref.getDownloadURL().timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> delete(String storagePath) {
    return storage
        .ref()
        .child(storagePath)
        .delete()
        .timeout(const Duration(seconds: 20));
  }
}
