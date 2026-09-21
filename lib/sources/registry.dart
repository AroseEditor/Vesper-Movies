import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';
import 'bdix/circleftp_source.dart';
import 'bdix/dhakaflix_source.dart';
import 'content_source.dart';
import 'dramachi/dramachi_source.dart';
import 'moviebox/moviebox_source.dart';

typedef SourceOutcome = ({ProviderKind kind, List<CatalogItem> items, SourceError? error});

final sourceRegistryProvider = Provider<Map<ProviderKind, ContentSource>>((ref) {
  return {
    ProviderKind.moviebox: MovieBoxSource(),
    ProviderKind.dramachi: DramachiSource(),
    ProviderKind.circleftp: CircleFtpSource(),
    ProviderKind.dhakaflix: DhakaFlixSource(),
  };
});

final enabledSourcesProvider = Provider<List<ProviderKind>>((ref) {
  return ref.watch(sourceRegistryProvider).keys.toList();
});

class SearchQuery {
  const SearchQuery(this.text, {this.page = 1});

  final String text;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.text == text && other.page == page;

  @override
  int get hashCode => Object.hash(text, page);
}

final searchResultsProvider = FutureProvider.autoDispose.family<List<SourceOutcome>, SearchQuery>((
  ref,
  query,
) async {
  final trimmed = query.text.trim();
  if (trimmed.isEmpty) return const [];

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final registry = ref.watch(sourceRegistryProvider);

  final futures = registry.entries.map((entry) async {
    try {
      final items = await entry.value.search(trimmed, page: query.page, cancel: cancel);
      return (kind: entry.key, items: items, error: null as SourceError?);
    } on SourceError catch (error) {
      return (kind: entry.key, items: const <CatalogItem>[], error: error);
    } on Object catch (_) {
      return (
        kind: entry.key,
        items: const <CatalogItem>[],
        error: const Unavailable() as SourceError?,
      );
    }
  });

  return Future.wait(futures);
});

final mediaDetailsProvider = FutureProvider.autoDispose.family<MediaDetails, MediaId>((
  ref,
  id,
) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final source = ref.watch(sourceRegistryProvider)[id.kind];
  if (source == null) throw const Unavailable();

  return source.details(id.value, cancel: cancel);
});

List<CatalogItem> flattenOutcomes(List<SourceOutcome> outcomes) {
  final items = <CatalogItem>[];
  final seen = <String>{};

  for (final outcome in outcomes) {
    for (final item in outcome.items) {
      if (seen.add('${item.id.kind.id}:${item.id.value}')) items.add(item);
    }
  }

  return items;
}
