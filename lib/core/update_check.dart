import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

const releasesApi = 'https://api.github.com/repos/AroseEditor/Vesper-Movies/releases/latest';
const releasesPage = 'https://github.com/AroseEditor/Vesper-Movies/releases/latest';

class UpdateInfo {
  const UpdateInfo({required this.current, required this.latest, required this.url});

  final String current;
  final String latest;
  final String url;

  bool get isNewer => compareVersions(latest, current) > 0;
}

List<int> _parts(String version) {
  final core = version.trim().replaceFirst(RegExp('^[vV]'), '').split(RegExp(r'[+\-]')).first;
  return [for (final part in core.split('.')) int.tryParse(part) ?? 0];
}

int compareVersions(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  try {
    final info = await PackageInfo.fromPlatform();
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {'Accept': 'application/vnd.github+json'},
      ),
    ).get<Map<String, dynamic>>(releasesApi, cancelToken: cancel);

    final data = response.data;
    final tag = data?['tag_name'];
    if (tag is! String || tag.isEmpty) return null;

    final url = data?['html_url'];
    return UpdateInfo(
      current: info.version,
      latest: tag.replaceFirst(RegExp('^[vV]'), ''),
      url: url is String && url.startsWith('https://github.com/') ? url : releasesPage,
    );
  } on Object {
    return null;
  }
});
