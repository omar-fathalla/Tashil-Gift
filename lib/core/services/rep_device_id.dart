import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable per-browser rep identifier saved on new receipts (`rep_device_id`).
///
/// The Firebase anonymous uid changes on sign-out or a new session, which hid
/// a rep's own history; this id survives sign-out / anonymous re-sign-in on
/// the same browser (it is lost only if site storage is cleared).
class RepDeviceId {
  static const _key = 'rep_device_id_v1';
  static String _value = '';

  static String get value => _value;

  static Future<void> init() async {
    if (_value.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var v = prefs.getString(_key) ?? '';
      if (v.isEmpty) {
        final r = Random.secure();
        v = 'rd_${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        await prefs.setString(_key, v);
      }
      _value = v;
    } catch (_) {}
  }
}
