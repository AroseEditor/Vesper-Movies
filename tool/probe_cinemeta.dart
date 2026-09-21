// ignore_for_file: avoid_print

import 'package:dio/dio.dart';

const _shelves = ['movie/top', 'series/top', 'movie/year', 'movie/imdbRating'];

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  for (final shelf in _shelves) {
    final started = DateTime.now();
    try {
      final response = await dio.get<dynamic>('https://v3-cinemeta.strem.io/catalog/$shelf.json');
      final ms = DateTime.now().difference(started).inMilliseconds;
      final data = response.data;
      final metas = data is Map ? (data['metas'] as List?)?.length : null;
      print('$shelf -> ${response.statusCode} ${data.runtimeType} metas=$metas in ${ms}ms');
    } on Object catch (error) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      print('$shelf -> FAILED in ${ms}ms: $error');
    }
  }
}
