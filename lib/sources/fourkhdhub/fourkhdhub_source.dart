import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../bdix/circleftp_source.dart';
import '../content_source.dart';
import '../links/hosts.dart';
import '../links/web.dart';
import '../moviebox/adapt.dart';

const String fourKHdHubBase = 'https://4khdhub.one';
const String browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

abstract final class FourKSelectors {
  static const card = 'a.movie-card';
  static const cardTitle = '.movie-card-title';
  static const metadataItem = '.metadata-item';
  static const downloadItem = '.download-item';
  static const episodeItem = '#episodes .episode-download-item';
  static const fileTitle = '.file-title';
  static const badgeSize = '.badge-size';
}

class FourKHdHubSource extends BaseContentSource {
  FourKHdHubSource({Dio? dio, String? baseUrl})
    : _base = baseUrl ?? fourKHdHubBase,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 25),
              responseType: ResponseType.plain,
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 500,
              headers: {'User-Agent': browserUserAgent},
            ),
          );

  final Dio _dio;
  final String _base;
  final HostResolver _hosts = HostResolver(Web());

  @override
  ProviderKind get kind => ProviderKind.fourkhdhub;

  @override
  SourceCapabilities get capabilities =>
      const SourceCapabilities(pagination: false, subtitles: false);

  @override
  Future<List<CatalogItem>> search(String query, {int page = 1, CancelToken? cancel}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final document = await _fetch('$_base/?s=${Uri.encodeQueryComponent(trimmed)}', cancel);
    return parseSearch(document, kind);
  }

  @override
  Future<MediaDetails> details(String id, {CancelToken? cancel}) async {
    final document = await _fetch(_absolute(id), cancel);
    return parseDetails(document, id, kind);
  }

  @override
  Future<List<Release>> releases(
    String id, {
    int season = 0,
    int episode = 0,
    CancelToken? cancel,
  }) async {
    final document = await _fetch(_absolute(id), cancel);
    final releases = parseReleases(document, kind, season: season, episode: episode);

    if (releases.isEmpty) throw const Unavailable();
    return sortReleases(releases);
  }

  @override
  Future<PlaybackSource> resolve(Release release, {CancelToken? cancel}) async {
    final mirror = release.mirrors.first;
    if (mirror.directFile) return super.resolve(release, cancel: cancel);
    final files = await _hosts.resolve(mirror.url, referer: fourKHdHubBase, cancel: cancel);
    if (files.isEmpty) throw const Unavailable();
    final file = files.first;
    return PlaybackSource(
      kind: kind,
      url: file.url,
      headers: {'User-Agent': webUserAgent, ...file.headers},
      sourceLabel: '4KHDHub ${file.server}',
    );
  }

  String _absolute(String path) {
    if (path.startsWith('http')) return path;
    return '$_base/${path.startsWith('/') ? path.substring(1) : path}';
  }

  Future<Document> _fetch(String url, CancelToken? cancel) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancel,
        options: Options(headers: {'Referer': _base}),
      );
      final status = response.statusCode ?? 0;
      if (status == 404) throw const NotFound();
      if (status < 200 || status >= 300) throw Unavailable(status);

      return html.parse('${response.data}');
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const Cancelled();
      throw NetworkError(
        error.type.name,
        timedOut: error.type == DioExceptionType.connectionTimeout,
      );
    }
  }
}

List<CatalogItem> parseSearch(Document document, ProviderKind kind) {
  final items = <CatalogItem>[];
  final seen = <String>{};

  for (final card in document.querySelectorAll(FourKSelectors.card)) {
    final href = card.attributes['href'];
    if (href == null || href.isEmpty) continue;

    final id = href.startsWith('http') ? Uri.parse(href).path : href;
    if (!seen.add(id)) continue;

    final title = card.querySelector(FourKSelectors.cardTitle)?.text.trim();
    if (title == null || title.isEmpty) continue;

    final metadata = card
        .querySelectorAll(FourKSelectors.metadataItem)
        .map((e) => e.text.trim())
        .toList();
    final year = extractYear(metadata.join(' '));
    final isSeries = metadata.any(
      (e) => e.toLowerCase().contains('season') || e.toLowerCase().contains('series'),
    );

    final poster = card.querySelector('img')?.attributes['src'];

    items.add(
      CatalogItem(
        id: MediaId(kind, id),
        title: title,
        mediaType: isSeries ? MediaType.series : MediaType.movie,
        year: year.isEmpty ? null : year,
        posterUrl: poster != null && poster.startsWith('http') ? poster : null,
      ),
    );
  }

  return items;
}

MediaDetails parseDetails(Document document, String id, ProviderKind kind) {
  final title =
      document.querySelector('h1')?.text.trim() ??
      document.querySelector(FourKSelectors.cardTitle)?.text.trim() ??
      'Unknown';

  final metadata = document
      .querySelectorAll(FourKSelectors.metadataItem)
      .map((e) => e.text.trim())
      .toList();

  final episodes = document.querySelectorAll(FourKSelectors.episodeItem);
  final seasons = <int, List<Episode>>{};

  for (final node in episodes) {
    final label = node.text;
    final marker = parseSeasonEpisode(label);
    if (marker == null) continue;

    seasons
        .putIfAbsent(marker.season, () => <Episode>[])
        .add(Episode(season: marker.season, number: marker.episode));
  }

  final ordered = seasons.entries.map((entry) {
    final list = [...entry.value]..sort((a, b) => a.number.compareTo(b.number));
    return Season(number: entry.key, episodes: list);
  }).toList()..sort((a, b) => a.number.compareTo(b.number));

  final year = extractYear(metadata.join(' '));

  return MediaDetails(
    id: MediaId(kind, id),
    title: title,
    mediaType: ordered.isEmpty ? MediaType.movie : MediaType.series,
    year: year.isEmpty ? null : year,
    description: document.querySelector('.description, .synopsis, .plot')?.text.trim(),
    seasons: ordered,
  );
}

List<Release> parseReleases(
  Document document,
  ProviderKind kind, {
  int season = 0,
  int episode = 0,
}) {
  final releases = <Release>[];
  final seen = <String>{};

  final scope = season > 0
      ? document.querySelectorAll(FourKSelectors.episodeItem)
      : document.querySelectorAll(FourKSelectors.downloadItem);

  for (final node in scope) {
    if (season > 0) {
      final marker = parseSeasonEpisode(node.text);
      if (marker == null) continue;
      if (marker.season != season) continue;
      if (episode > 0 && marker.episode != episode) continue;
    }

    final name =
        node.querySelector(FourKSelectors.fileTitle)?.text.trim() ??
        node.text.trim().split('\n').first.trim();
    final size = node.querySelector(FourKSelectors.badgeSize)?.text.trim();

    for (final anchor in node.querySelectorAll('a')) {
      final href = anchor.attributes['href'];
      if (href == null || !href.startsWith('http')) continue;
      if (!isPlayableMirror(href)) continue;
      if (!seen.add(href)) continue;

      releases.add(
        Release(
          kind: kind,
          filename: name.isEmpty ? 'Release' : name,
          quality: qualityFromFilename(name),
          codec: codecFromFilename(name),
          sizeBytes: parseSizeLabel(size),
          season: season == 0 ? null : season,
          episode: episode == 0 ? null : episode,
          mirrors: [
            SourceMirror(
              label: isDirectMirror(href) ? mirrorLabel(href) : '${mirrorLabel(href)} (redirect)',
              url: href,
              headers: const {'Referer': fourKHdHubBase, 'User-Agent': browserUserAgent},
              directFile: isDirectMirror(href),
            ),
          ],
        ),
      );
    }
  }

  releases.sort((a, b) {
    final aDirect = a.mirrors.first.directFile ? 0 : 1;
    final bDirect = b.mirrors.first.directFile ? 0 : 1;
    return aDirect.compareTo(bDirect);
  });

  return releases;
}

({int season, int episode})? parseSeasonEpisode(String text) {
  final match = RegExp(r'[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})').firstMatch(text);
  if (match == null) return null;

  final season = int.tryParse(match.group(1) ?? '');
  final episode = int.tryParse(match.group(2) ?? '');
  if (season == null || episode == null) return null;

  return (season: season, episode: episode);
}

const Set<String> blockedMirrorHosts = {'localhost', '127.0.0.1', '0.0.0.0'};

bool isPlayableMirror(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isScheme('https')) return false;
  if (blockedMirrorHosts.contains(uri.host)) return false;
  if (uri.host.startsWith('192.168.') || uri.host.startsWith('10.')) {
    return false;
  }

  final path = uri.path.toLowerCase();
  if (path.endsWith('.zip') || path.endsWith('.rar') || path.contains('login.php')) {
    return false;
  }

  return true;
}

const Set<String> directMirrorHosts = {
  'pixeldrain.dev',
  'pixeldrain.com',
  'workers.dev',
  'googleusercontent.com',
  'r2.dev',
};

bool isDirectMirror(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return directMirrorHosts.any((known) => host == known || host.endsWith('.$known'));
}

String mirrorLabel(String url) {
  final host = Uri.tryParse(url)?.host ?? '4KHDHub';
  final parts = host.split('.');
  if (parts.length < 2) return host;
  final name = parts[parts.length - 2];
  return name.isEmpty ? host : '${name[0].toUpperCase()}${name.substring(1)}';
}

int? parseSizeLabel(String? label) {
  if (label == null || label.isEmpty) return null;

  final match = RegExp(r'([\d.]+)\s*(B|KB|MB|GB|TB)', caseSensitive: false).firstMatch(label);
  if (match == null) return null;

  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return null;

  final unit = (match.group(2) ?? 'B').toUpperCase();
  const multipliers = {
    'B': 1,
    'KB': 1024,
    'MB': 1024 * 1024,
    'GB': 1024 * 1024 * 1024,
    'TB': 1024 * 1024 * 1024 * 1024,
  };

  return (value * (multipliers[unit] ?? 1)).round();
}
