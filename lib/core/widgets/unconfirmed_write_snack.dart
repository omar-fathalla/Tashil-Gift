import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/confirmed_write.dart';

/// TAG-35 (N-01b): «الحفظ لسه ما اتأكدش» with «تحقق», which reads the
/// document from the server (never the cache) and calls [onConfirmed] only
/// when the server copy proves the write. A batch ([WriteNotConfirmedException.path]
/// empty) has nothing to read back, so it only shows the message.
void showUnconfirmedWriteSnack(
  ScaffoldMessengerState messenger,
  FirebaseFirestore firestore,
  WriteNotConfirmedException e, {
  VoidCallback? onConfirmed,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: const Text(WriteNotConfirmedException.message),
      duration: const Duration(seconds: 20),
      behavior: SnackBarBehavior.floating,
      action: e.path.isEmpty
          ? null
          : SnackBarAction(
              label: 'تحقق',
              onPressed: () async {
                try {
                  final snap = await firestore.doc(e.path).get(const GetOptions(source: Source.server));
                  final done = e.isDelete ? !snap.exists : snap.exists;
                  if (done) {
                    messenger.showSnackBar(const SnackBar(content: Text('اتأكد: الحفظ وصل للسيرفر.')));
                    onConfirmed?.call();
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('لسه ما وصلش للسيرفر. جرّب تاني بعد ما النت يرجع.')),
                    );
                  }
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('تعذر الوصول للسيرفر للتحقق. اتأكد من النت وجرّب تاني.')),
                  );
                }
              },
            ),
    ),
  );
}
