import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/release.dart';

const _userAgent = 'VesperMovies v1.0';

Future<List<SubtitleOption>> fetchOpenSubtitles(
  String imdbId, {
  int? season,
  int? episode,
  CancelToken? cancel,
}) async {
  final numeric = imdbId.replaceFirst('tt', '').padLeft(7, '0');
  if (int.tryParse(numeric) == null) return const [];

  final segments = ['imdbid-$numeric'];
  if (season != null && season > 0) segments.add('season-$season');
  if (episode != null && episode > 0) segments.add('episode-$episode');
  segments.add('sublanguageid-eng');

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'User-Agent': _userAgent},
    ),
  );

  try {
    final response = await dio.get<List<dynamic>>(
      'https://rest.opensubtitles.org/search/${segments.join('/')}',
      cancelToken: cancel,
    );
    final results = response.data?.whereType<Map>().toList() ?? const [];
    if (results.isEmpty) return const [];

    results.sort((a, b) => _downloads(b).compareTo(_downloads(a)));
    final link = results.first['SubDownloadLink'] as String?;
    if (link == null) return const [];

    final path = await _downloadAndDecompress(dio, link, cancel);
    if (path == null) return const [];
    return [SubtitleOption(name: 'English (auto-fetched)', url: Uri.file(path).toString())];
  } on Object {
    return const [];
  } finally {
    dio.close();
  }
}

int _downloads(Map entry) => int.tryParse('${entry['SubDownloadsCnt']}') ?? 0;

Future<String?> _downloadAndDecompress(Dio dio, String gzUrl, CancelToken? cancel) async {
  try {
    final response = await dio.get<List<int>>(
      gzUrl,
      cancelToken: cancel,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null) return null;

    final decoded = gzip.decode(bytes);
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'vesper_sub_${DateTime.now().microsecondsSinceEpoch}.srt'),
    );
    await file.writeAsBytes(decoded, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}
