import 'dart:async';

import 'package:flutter/material.dart';

/// 2.0.172: replaces bare centered spinners on slow admin pages.
/// Shows an M3 LinearProgressIndicator over skeleton rows, and after
/// [timeout] a "still loading" message with an optional retry action.
class SlowLoadPlaceholder extends StatefulWidget {
  final Duration timeout;
  final VoidCallback? onRetry;
  final int rows;
  final String? message;

  const SlowLoadPlaceholder({
    super.key,
    this.timeout = const Duration(seconds: 20),
    this.onRetry,
    this.rows = 6,
    this.message,
  });

  @override
  State<SlowLoadPlaceholder> createState() => _SlowLoadPlaceholderState();
}

class _SlowLoadPlaceholderState extends State<SlowLoadPlaceholder> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.maybeLocaleOf(context)?.languageCode != 'en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        if (_slow)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.hourglass_bottom_rounded, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message ??
                        (isAr
                            ? 'التحميل بياخد وقت أطول من المعتاد. تقدر تستنى أو تعيد المحاولة.'
                            : 'This is taking longer than usual. Wait or retry.'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (widget.onRetry != null)
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => _slow = false);
                      _timer?.cancel();
                      _timer = Timer(widget.timeout, () {
                        if (mounted) setState(() => _slow = true);
                      });
                      widget.onRetry!();
                    },
                    child: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: widget.rows,
            itemBuilder: (_, i) => Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
