import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/firebase_service.dart';
import '../../data/campaign_content_repository.dart';
import '../../domain/event_model.dart';

/// TAG-62: builds with the campaign's products/prompt. Inline content builds
/// at once; content in events/{id}/content is read only when this widget is
/// built (e.g. when a collapsed panel is opened), never for the whole list.
class CampaignContentBuilder extends ConsumerStatefulWidget {
  const CampaignContentBuilder({super.key, required this.event, required this.builder});

  final EventModel event;
  final Widget Function(BuildContext context, CampaignContent content) builder;

  @override
  ConsumerState<CampaignContentBuilder> createState() => _CampaignContentBuilderState();
}

class _CampaignContentBuilderState extends ConsumerState<CampaignContentBuilder> {
  Future<CampaignContent>? _future;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CampaignContentBuilder old) {
    super.didUpdateWidget(old);
    if (old.event.id != widget.event.id || old.event.contentInfo.version != widget.event.contentInfo.version) {
      _start();
    }
  }

  void _start() {
    _future = widget.event.contentInfo.needsLoad
        ? CampaignContentRepository(ref.read(firestoreProvider)).load(widget.event)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return widget.builder(
        context,
        CampaignContent(products: widget.event.requiredProducts, prompt: widget.event.customPrompt),
      );
    }
    return FutureBuilder<CampaignContent>(
      future: future,
      builder: (context, snap) {
        if (snap.hasData) return widget.builder(context, snap.data!);
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'تعذر تحميل منتجات الحملة وتعليماتها.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        );
      },
    );
  }
}
