import 'package:flutter/material.dart';

import '../config/app_env.dart';

/// Wraps the whole app with a corner "DEV" ribbon on APP_ENV=dev builds, so a
/// dev page is never mistaken for production. In prod (the default build)
/// [enabled] is false and [child] is returned untouched.
class EnvBadge extends StatelessWidget {
  const EnvBadge({super.key, required this.child, this.enabled = kIsDevEnv});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Banner(
      message: 'DEV',
      location: BannerLocation.topStart,
      color: Theme.of(context).colorScheme.error,
      textDirection: TextDirection.ltr,
      layoutDirection: TextDirection.ltr,
      child: child,
    );
  }
}
