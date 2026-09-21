import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

String safeFileName(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes.take(120)) {
    final char = String.fromCharCode(rune);
    final forbidden = r'/\:*?"<>|'.contains(char) || rune < 0x20;
    buffer.write(forbidden ? '_' : char);
  }

  var name = buffer.toString().trim();
  while (name.endsWith('.') || name.endsWith(' ') || name.endsWith('_')) {
    name = name.substring(0, name.length - 1);
  }
  if (name.isEmpty) return 'Vesper_Download';

  const reserved = {'CON', 'PRN', 'AUX', 'NUL'};
  final upper = name.toUpperCase();
  final isReservedPort =
      (upper.startsWith('COM') || upper.startsWith('LPT')) &&
      upper.length == 4 &&
      int.tryParse(upper.substring(3)) != null;

  if (reserved.contains(upper) || isReservedPort) return '${name}_';
  return name;
}

String extensionForUrl(String url, {String fallback = 'mp4'}) {
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return fallback;

  final extension = path.substring(dot + 1).toLowerCase();
  const known = {'mp4', 'mkv', 'avi', 'webm', 'mov', 'm4v', 'ts'};
  return known.contains(extension) ? extension : fallback;
}

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });

  final int received;
  final int total;
  final double bytesPerSecond;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

typedef ProgressCallback = void Function(DownloadProgress progress);

class DownloadEngine {
  DownloadEngine({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 5),
              responseType: ResponseType.stream,
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<void> download({
    required String url,
    required File destination,
    Map<String, String> headers = const {},
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final partial = File('${destination.path}.part');
    var offset = partial.existsSync() ? await partial.length() : 0;

    final requestHeaders = <String, String>{...headers};
    if (offset > 0) requestHeaders['Range'] = 'bytes=$offset-';

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(headers: requestHeaders, responseType: ResponseType.stream),
    );

    final status = response.statusCode ?? 0;
    if (status == 416) {
      await _finalise(partial, destination);
      return;
    }
    if (status < 200 || status >= 300) {
      throw HttpException('status $status');
    }

    if (offset > 0 && status != 206) {
      if (partial.existsSync()) await partial.delete();
      offset = 0;
    }

    final contentLength = int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    final total = contentLength > 0 ? contentLength + offset : 0;

    final sink = partial.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    var received = offset;
    var lastTick = DateTime.now();
    var lastBytes = received;

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;

        final now = DateTime.now();
        final elapsed = now.difference(lastTick);
        if (elapsed.inMilliseconds >= 400) {
          final speed = (received - lastBytes) / (elapsed.inMilliseconds / 1000);
          onProgress?.call(
            DownloadProgress(received: received, total: total, bytesPerSecond: speed),
          );
          lastTick = now;
          lastBytes = received;
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    await _finalise(partial, destination);
    onProgress?.call(
      DownloadProgress(received: received, total: total == 0 ? received : total, bytesPerSecond: 0),
    );
  }

  Future<void> _finalise(File partial, File destination) async {
    if (!partial.existsSync()) return;
    if (destination.existsSync()) await destination.delete();
    await partial.rename(destination.path);
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '';
  return '${formatBytes(bytesPerSecond.round())}/s';
}
