import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants/app_version_config.dart';
import 'page_reload.dart';

/// Public, form-heavy routes (invoice upload etc.) where an update prompt must
/// never interrupt the user.
const Set<String> kUpdatePromptExcludedPaths = {
  '/c',
  '/submit',
  '/client',
  '/promoter',
};

/// Returns true when [remoteJson] (contents of `/version.json`) describes a
/// newer build than [currentBuild].
@visibleForTesting
bool isNewerBuild(String remoteJson, int currentBuild) {
  try {
    final data = jsonDecode(remoteJson);
    if (data is! Map) return false;
    final raw = data['build_number'];
    final remote = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim());
    return remote != null && remote > currentBuild;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
bool isUpdatePromptAllowedForPath(String path) {
  var p = path.trim();
  if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
  return !kUpdatePromptExcludedPaths.contains(p.toLowerCase());
}

/// Web-only: polls `/version.json` (served no-cache) and shows a non-blocking
/// SnackBar with a reload action when a newer build is deployed. It never
/// reloads automatically.
class AppUpdateChecker {
  AppUpdateChecker({
    required this.messengerKey,
    this.interval = const Duration(minutes: 5),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Duration interval;
  final http.Client _client;
  Timer? _timer;
  bool _prompted = false;

  void start() {
    if (!kIsWeb || _timer != null) return;
    Future<void>.delayed(const Duration(seconds: 30), check);
    _timer = Timer.periodic(interval, (_) => check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> check() async {
    if (_prompted) return;
    if (!isUpdatePromptAllowedForPath(Uri.base.path)) return;
    try {
      final uri = Uri.base.replace(
        path: '/version.json',
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
        fragment: '',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      if (!isNewerBuild(res.body, AppVersionConfig.buildNumber)) return;
      _showPrompt();
    } catch (_) {
      // Network hiccups are ignored; we try again on the next tick.
    }
  }

  void _showPrompt() {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    _prompted = true;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('يوجد إصدار جديد'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 1),
        showCloseIcon: true,
        action: SnackBarAction(label: 'تحديث', onPressed: reloadPage),
      ),
    );
  }
}
