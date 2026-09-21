import 'package:dio/dio.dart';

import '../models/media.dart';
import '../models/provider_kind.dart';
import '../models/release.dart';

abstract interface class ContentSource {
  ProviderKind get kind;

  SourceCapabilities get capabilities;

  Future<List<CatalogItem>> search(String query, {int page = 1, CancelToken? cancel});

  Future<MediaDetails> details(String id, {CancelToken? cancel});

  Future<List<Release>> releases(String id, {int season = 0, int episode = 0, CancelToken? cancel});

  Future<List<SubtitleOption>> subtitles(
    String id, {
    String? resourceId,
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  });

  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel});
}

abstract class BaseContentSource implements ContentSource {
  const BaseContentSource();

  @override
  SourceCapabilities get capabilities => const SourceCapabilities();

  @override
  Future<List<SubtitleOption>> subtitles(
    String id, {
    String? resourceId,
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    return const [];
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final mirror = release.mirrors.first;
    return PlaybackSource(
      kind: release.kind,
      url: mirror.url,
      headers: mirror.headers,
      sourceLabel: mirror.label,
    );
  }
}
