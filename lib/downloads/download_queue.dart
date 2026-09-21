import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/log.dart';
import '../models/media.dart';
import '../models/release.dart';
import 'download_engine.dart';

enum DownloadStatus { queued, running, paused, completed, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.filePath,
    this.subtitle,
    this.posterUrl,
    this.headers = const {},
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = 0,
    this.speed = 0,
    this.error,
  });

  final String id;
  final String title;
  final String url;
  final String filePath;
  final String? subtitle;
  final String? posterUrl;
  final Map<String, String> headers;
  final DownloadStatus status;
  final int received;
  final int total;
  final double speed;
  final String? error;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);

  bool get isActive =>
      status == DownloadStatus.running || status == DownloadStatus.queued;

  DownloadTask copyWith({
    DownloadStatus? status,
    int? received,
    int? total,
    double? speed,
    String? error,
    bool clearError = false,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      url: url,
      filePath: filePath,
      subtitle: subtitle,
      posterUrl: posterUrl,
      headers: headers,
      status: status ?? this.status,
      received: received ?? this.received,
      total: total ?? this.total,
      speed: speed ?? this.speed,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'filePath': filePath,
    'subtitle': subtitle,
    'posterUrl': posterUrl,
    'headers': headers,
    'status': status.name,
    'received': received,
    'total': total,
  };

  static DownloadTask? fromJson(Object? source) {
    if (source is! Map) return null;
    final id = source['id'];
    final url = source['url'];
    final path = source['filePath'];
    if (id is! String || url is! String || path is! String) return null;

    final rawStatus = '${source['status']}';
    var status = DownloadStatus.values.firstWhere(
      (e) => e.name == rawStatus,
      orElse: () => DownloadStatus.paused,
    );
    if (status == DownloadStatus.running || status == DownloadStatus.queued) {
      status = DownloadStatus.paused;
    }

    return DownloadTask(
      id: id,
      title: source['title'] is String ? source['title'] as String : 'Download',
      url: url,
      filePath: path,
      subtitle: source['subtitle'] as String?,
      posterUrl: source['posterUrl'] as String?,
      headers: {
        for (final entry in (source['headers'] as Map? ?? const {}).entries)
          '${entry.key}': '${entry.value}',
      },
      status: status,
      received: source['received'] is int ? source['received'] as int : 0,
      total: source['total'] is int ? source['total'] as int : 0,
    );
  }
}

class DownloadQueueNotifier extends AsyncNotifier<List<DownloadTask>> {
  final Map<String, CancelToken> _tokens = {};
  final DownloadEngine _engine = DownloadEngine();

  @override
  Future<List<DownloadTask>> build() async {
    ref.onDispose(() {
      for (final token in _tokens.values) {
        token.cancel();
      }
    });
    return _load();
  }

  Future<Directory> _downloadsDirectory() async {
    final base =
        await getDownloadsDirectory() ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'Vesper Movies'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'downloads.json'));
  }

  Future<List<DownloadTask>> _load() async {
    try {
      final file = await _stateFile();
      if (!file.existsSync()) return const [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];

      final tasks = <DownloadTask>[];
      for (final entry in decoded) {
        final parsed = DownloadTask.fromJson(entry);
        if (parsed != null) tasks.add(parsed);
      }
      return tasks;
    } on Object catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<DownloadTask> tasks) async {
    try {
      final file = await _stateFile();
      await file.writeAsString(
        jsonEncode(tasks.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } on Object catch (_) {
      return;
    }
  }

  List<DownloadTask> get _current => state.value ?? const [];

  void _update(DownloadTask task, {bool persist = true}) {
    final next = [
      for (final entry in _current)
        if (entry.id == task.id) task else entry,
    ];
    state = AsyncValue.data(next);
    if (persist) unawaited(_persist(next));
  }

  Future<String?> enqueue({
    required CatalogItem item,
    required Release release,
    required Map<String, String> headers,
    required String url,
    int season = 0,
    int episode = 0,
  }) async {
    if (url.contains('.mpd') || url.contains('.m3u8')) {
      return 'Adaptive streams cannot be saved yet. Pick a direct file if one is listed.';
    }

    final suffix = season > 0 ? ' S${season}E$episode' : '';
    final title = '${item.title}$suffix';
    final id = '${item.id.value}:$season:$episode';

    if (_current.any((e) => e.id == id)) {
      return 'That is already in your downloads.';
    }

    final dir = await _downloadsDirectory();
    final name = '${safeFileName(title)}.${extensionForUrl(url)}';
    final task = DownloadTask(
      id: id,
      title: title,
      url: url,
      filePath: p.join(dir.path, name),
      subtitle: season > 0 ? 'S${season}E$episode' : null,
      posterUrl: item.posterUrl,
      headers: headers,
    );

    final next = [task, ..._current];
    state = AsyncValue.data(next);
    await _persist(next);

    unawaited(start(task.id));
    return null;
  }

  Future<void> start(String id) async {
    final task = _current.where((e) => e.id == id).firstOrNull;
    if (task == null || task.status == DownloadStatus.completed) return;

    final token = CancelToken();
    _tokens[id] = token;
    _update(
      task.copyWith(status: DownloadStatus.running, clearError: true),
      persist: false,
    );

    try {
      await _engine.download(
        url: task.url,
        destination: File(task.filePath),
        headers: task.headers,
        cancel: token,
        onProgress: (progress) {
          final latest = _current.where((e) => e.id == id).firstOrNull;
          if (latest == null || latest.status != DownloadStatus.running) return;
          _update(
            latest.copyWith(
              received: progress.received,
              total: progress.total,
              speed: progress.bytesPerSecond,
            ),
            persist: false,
          );
        },
      );

      final latest = _current.where((e) => e.id == id).firstOrNull ?? task;
      _update(latest.copyWith(status: DownloadStatus.completed, speed: 0));
    } on Object catch (error) {
      final latest = _current.where((e) => e.id == id).firstOrNull ?? task;
      final cancelled = error is DioException && CancelToken.isCancel(error);
      if (cancelled) {
        _update(latest.copyWith(status: DownloadStatus.paused, speed: 0));
      } else {
        log.warn('download failed: ${describeCause(error)}');
        _update(
          latest.copyWith(
            status: DownloadStatus.failed,
            speed: 0,
            error: 'The download stopped before it finished.',
          ),
        );
      }
    } finally {
      _tokens.remove(id);
    }
  }

  Future<void> pause(String id) async {
    _tokens.remove(id)?.cancel();
    final task = _current.where((e) => e.id == id).firstOrNull;
    if (task == null) return;
    _update(task.copyWith(status: DownloadStatus.paused, speed: 0));
  }

  Future<void> remove(String id) async {
    _tokens.remove(id)?.cancel();

    final task = _current.where((e) => e.id == id).firstOrNull;
    if (task != null) {
      for (final path in [task.filePath, '${task.filePath}.part']) {
        final file = File(path);
        if (file.existsSync()) {
          try {
            await file.delete();
          } on Object catch (_) {
            continue;
          }
        }
      }
    }

    final next = _current.where((e) => e.id != id).toList();
    state = AsyncValue.data(next);
    await _persist(next);
  }
}

final downloadQueueProvider =
    AsyncNotifierProvider<DownloadQueueNotifier, List<DownloadTask>>(
      DownloadQueueNotifier.new,
    );
