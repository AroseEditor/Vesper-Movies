import 'package:dio/dio.dart';

import '../../../models/provider_kind.dart';
import '../../../models/release.dart';
import '../link_source.dart';
import '../web.dart';

class ArchiveSource extends LinkSource {
  ArchiveSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.archive;

  static const _base = 'https://archive.org';

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final terms = Uri.encodeQueryComponent('title:("${query.title}") AND mediatype:(movies)');
    final data = await web.json(
      '$_base/advancedsearch.php?q=$terms&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=year'
      '&rows=12&sort%5B%5D=downloads+desc&output=json',
      cancel: cancel,
    );
    final response = data is Map ? data['response'] : null;
    final docs = response is Map ? response['docs'] : null;
    if (docs is! List) return const [];

    final wantedYear = int.tryParse(query.year ?? '');
    final hits = <(String, String)>[];
    for (final doc in docs) {
      if (doc is! Map) continue;
      final id = '${doc['identifier'] ?? ''}';
      final title = cleanText('${doc['title'] ?? ''}');
      if (id.isEmpty || title.isEmpty) continue;
      if (!strictTitle(query.title, title)) continue;
      final listed = int.tryParse('${doc['year'] ?? ''}');
      if (!query.isEpisode && wantedYear != null && listed != null) {
        if ((wantedYear - listed).abs() > 1) continue;
      }
      hits.add((id, title));
    }

    final jobs = [for (final hit in hits.take(4)) _files(hit.$1, hit.$2, query, cancel)];
    final found = await Future.wait(jobs);
    return dedupeReleases([for (final group in found) ...group]);
  }

  Future<List<Release>> _files(
    String id,
    String title,
    LinkQuery query,
    CancelToken? cancel,
  ) async {
    try {
      final data = await web.json('$_base/metadata/$id', cancel: cancel);
      final files = data is Map ? data['files'] : null;
      if (files is! List) return const [];

      final episode = query.isEpisode
          ? RegExp(
              'S0*${query.season}[ ._-]*E0*${query.episode}\\b|'
              '\\b0*${query.season}x0*${query.episode}\\b|'
              'Episode[ ._-]*0*${query.episode}\\b',
              caseSensitive: false,
            )
          : null;

      final videos = <Map<dynamic, dynamic>>[];
      for (final file in files) {
        if (file is! Map) continue;
        final name = '${file['name'] ?? ''}';
        if (!name.toLowerCase().endsWith('.mp4')) continue;
        final size = int.tryParse('${file['size'] ?? ''}') ?? 0;
        if (size < 20 * 1024 * 1024) continue;
        final height = int.tryParse('${file['height'] ?? ''}') ?? 0;
        final width = int.tryParse('${file['width'] ?? ''}') ?? 0;
        if (height > 0 && height < 360) continue;
        if (width > 0 && width.isOdd) continue;
        if (episode != null && !episode.hasMatch(name)) continue;
        videos.add(file);
      }
      videos.sort((a, b) {
        final byHeight = (int.tryParse('${b['height'] ?? ''}') ?? 0).compareTo(
          int.tryParse('${a['height'] ?? ''}') ?? 0,
        );
        if (byHeight != 0) return byHeight;
        final left = int.tryParse('${a['size'] ?? ''}') ?? 0;
        final right = int.tryParse('${b['size'] ?? ''}') ?? 0;
        return right.compareTo(left);
      });

      return [
        for (final file in videos.take(2))
          release(
            _label(title, file),
            '$_base/download/$id/${Uri.encodeComponent('${file['name']}')}',
            query: query,
            direct: true,
          ),
      ];
    } on Object {
      return const [];
    }
  }

  String _label(String title, Map<dynamic, dynamic> file) {
    final height = int.tryParse('${file['height'] ?? ''}');
    final size = int.tryParse('${file['size'] ?? ''}') ?? 0;
    final megabytes = (size / (1024 * 1024)).round();
    return [title, if (height != null && height > 0) '${height}p', '$megabytes MB'].join(' ');
  }
}
