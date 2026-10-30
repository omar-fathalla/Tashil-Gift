import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_version_config.dart';
import 'page_reload.dart';

/// 2.0.150+211: rep pages (/c, /submit, /client, /promoter) now get the banner
/// too. Routes listed here never show it (none for now). Work in progress is
/// protected by [UpdatePromptGuard] instead.
const Set<String> kUpdatePromptExcludedPaths = {};

/// 2.0.150+211: marks a scan/save in progress. While busy the update banner is
/// not shown, and tapping 'تحديث' on an already-visible banner does not reload.
class UpdatePromptGuard {
  UpdatePromptGuard._();
  static int _active = 0;
  static bool get isBusy => _active > 0;
  static void begin() => _active++;
  static void end() {
    if (_active > 0) _active--;
  }

  @visibleForTesting
  static void resetForTest() => _active = 0;
}

/// A release identity: semantic version + build number, compared numerically.
@immutable
class BuildId implements Comparable<BuildId> {
  const BuildId(this.major, this.minor, this.patch, this.build);
  final int major, minor, patch, build;

  static const BuildId current = BuildId(AppVersionConfig.major,
      AppVersionConfig.minor, AppVersionConfig.patch, AppVersionConfig.buildNumber);

  /// Parses "2.0.136+191" (as stored for dismissals).
  static BuildId? tryParse(String? s) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch((s ?? '').trim());
    if (m == null) return null;
    return BuildId(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
  }

  /// Parses `/version.json` ({"version":"2.0.136","build_number":"191"}).
  static BuildId? fromVersionJson(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final v = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch('${data['version'] ?? ''}'.trim());
      final raw = data['build_number'];
      final b = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim());
      if (v == null || b == null) return null;
      return BuildId(int.parse(v[1]!), int.parse(v[2]!), int.parse(v[3]!), b);
    } catch (_) {
      return null;
    }
  }

  @override
  int compareTo(BuildId other) {
    final o = other;
    for (final d in [major - o.major, minor - o.minor, patch - o.patch, build - o.build]) {
      if (d != 0) return d.sign;
    }
    return 0;
  }

  bool operator >(BuildId o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is BuildId && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(major, minor, patch, build);
  @override
  String toString() => '$major.$minor.$patch+$build';
}

/// Decides whether to show the "new version" banner.
/// Shows only when [remote] is genuinely newer than [running] AND newer than
/// the last version the user already dismissed / tried to update to.
@visibleForTesting
bool shouldPromptForUpdate({
  required BuildId? remote,
  required BuildId running,
  BuildId? lastHandled,
}) {
  if (remote == null || !(remote > running)) return false;
  if (lastHandled != null && !(remote > lastHandled)) return false;
  return true;
}

/// Back-compat helper: true when [remoteJson] is newer than the running build.
@visibleForTesting
bool isNewerBuild(String remoteJson, int currentBuild) {
  final r = BuildId.fromVersionJson(remoteJson);
  if (r != null) {
    return shouldPromptForUpdate(
        remote: r,
        running: BuildId(AppVersionConfig.major, AppVersionConfig.minor,
            AppVersionConfig.patch, currentBuild));
  }
  try {
    final data = jsonDecode(remoteJson);
    if (data is! Map) return false;
    final raw = data['build_number'];
    final b = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim());
    return b != null && b > currentBuild;
  } catch (_) {
    return false;
  }
}

/// localStorage key (via shared_preferences on web) for the last version the
/// user dismissed or pressed "تحديث" for.
const String kUpdateHandledVersionKey = 'update_prompt_handled_version';

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
    this.interval = const Duration(minutes: 10),
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
    // Scan/save in progress: try again on the next tick.
    if (UpdatePromptGuard.isBusy) return;
    try {
      final uri = Uri.base.replace(
        path: '/version.json',
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
        fragment: '',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final remote = BuildId.fromVersionJson(res.body);
      final prefs = await SharedPreferences.getInstance();
      final handled = BuildId.tryParse(prefs.getString(kUpdateHandledVersionKey));
      if (!shouldPromptForUpdate(
          remote: remote, running: BuildId.current, lastHandled: handled)) {
        return;
      }
      _showPrompt(remote!, prefs);
    } catch (_) {
      // Network hiccups are ignored; we try again on the next tick.
    }
  }

  void _showPrompt(BuildId remote, SharedPreferences prefs) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    _prompted = true;
    // Remember this version as handled whether the user updates or closes the
    // banner, so it is never shown again for the same (or an older) version.
    Future<bool> markHandled() =>
        prefs.setString(kUpdateHandledVersionKey, remote.toString());
    messenger.showSnackBar(
      SnackBar(
        content: const Text('يوجد إصدار جديد'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 1),
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'تحديث',
          onPressed: () async {
            if (UpdatePromptGuard.isBusy) {
              // Never lose a scan/save: keep the banner for the next tick.
              _prompted = false;
              messenger.showSnackBar(const SnackBar(
                content: Text('استنى لحد ما الفاتورة تتحفظ، وبعدين حدّث'),
              ));
              return;
            }
            await markHandled();
            reloadPage();
          },
        ),
      ),
    ).closed.then((reason) {
      if (reason == SnackBarClosedReason.dismiss ||
          reason == SnackBarClosedReason.swipe) {
        markHandled();
      }
    });
  }
}
