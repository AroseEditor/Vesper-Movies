class ReleaseTags {
  const ReleaseTags({this.quality, this.codec, this.language, this.rip, this.sizeBytes});

  final String? quality;
  final String? codec;
  final String? language;
  final String? rip;
  final int? sizeBytes;

  bool get isCam => rip == 'CAM' || rip == 'HDTS' || rip == 'HDTC' || rip == 'PreDVD';
}

const _rips = [
  ('HDCAM', 'CAM'),
  ('CAMRIP', 'CAM'),
  ('CAM', 'CAM'),
  ('HDTS', 'HDTS'),
  ('TELESYNC', 'HDTS'),
  ('HDTC', 'HDTC'),
  ('TELECINE', 'HDTC'),
  ('PREDVD', 'PreDVD'),
  ('PRE-DVD', 'PreDVD'),
  ('WEB-DL', 'WEB-DL'),
  ('WEBDL', 'WEB-DL'),
  ('WEBRIP', 'WEBRip'),
  ('WEB', 'WEB-DL'),
  ('BLURAY', 'BluRay'),
  ('BLU-RAY', 'BluRay'),
  ('BDRIP', 'BluRay'),
  ('REMUX', 'Remux'),
  ('HDRIP', 'HDRip'),
  ('DVDRIP', 'DVDRip'),
  ('HDTV', 'HDTV'),
];

const _languages = [
  'Hindi',
  'Tamil',
  'Telugu',
  'Malayalam',
  'Kannada',
  'Bengali',
  'Marathi',
  'Punjabi',
  'Gujarati',
  'English',
  'Korean',
  'Japanese',
  'Spanish',
];

final _sizePattern = RegExp(r'([\d.]+)\s*(TB|GB|MB)\b', caseSensitive: false);
final _qualityPattern = RegExp(r'\b(2160|1440|1080|720|576|480|360)p\b', caseSensitive: false);

ReleaseTags parseReleaseTags(String raw) {
  final text = raw.replaceAll(RegExp(r'[._\[\]()|]+'), ' ');
  final upper = text.toUpperCase();

  String? quality;
  final q = _qualityPattern.firstMatch(text);
  if (q != null) {
    quality = '${q.group(1)}p';
  } else if (RegExp(r'\b(4K|UHD)\b').hasMatch(upper)) {
    quality = '2160p';
  }

  String? codec;
  if (RegExp(r'\b(HEVC|X265|H 265|H265)\b').hasMatch(upper)) {
    codec = 'HEVC';
  } else if (RegExp(r'\b(AV1)\b').hasMatch(upper)) {
    codec = 'AV1';
  } else if (RegExp(r'\b(X264|H 264|H264|AVC)\b').hasMatch(upper)) {
    codec = 'x264';
  }
  if (RegExp(r'\b10 ?BIT\b').hasMatch(upper)) codec = '${codec ?? 'HEVC'} 10bit';
  if (RegExp(r'\b(HDR|DV|DOVI|DOLBY VISION)\b').hasMatch(upper)) {
    codec = '${codec ?? ''} HDR'.trim();
  }

  String? rip;
  for (final (needle, label) in _rips) {
    if (RegExp('(^|[^A-Z])$needle([^A-Z]|\$)').hasMatch(upper)) {
      rip = label;
      break;
    }
  }

  final found = <String>[];
  for (final language in _languages) {
    if (RegExp('\b${language.toUpperCase()}\b').hasMatch(upper)) found.add(language);
  }
  String? language;
  if (found.length >= 3 || RegExp(r'\bMULTI ?AUDIO\b').hasMatch(upper)) {
    language = found.isEmpty ? 'Multi Audio' : 'Multi (${found.take(3).join(', ')})';
  } else if (found.length == 2) {
    language = '${found[0]} + ${found[1]}';
  } else if (found.length == 1) {
    language = found.first;
  } else if (RegExp(r'\bDUAL ?AUDIO\b').hasMatch(upper)) {
    language = 'Dual Audio';
  }

  int? size;
  final s = _sizePattern.firstMatch(text);
  if (s != null) {
    final value = double.tryParse(s.group(1) ?? '');
    if (value != null) {
      const units = {'MB': 1024 * 1024, 'GB': 1024 * 1024 * 1024, 'TB': 1024 * 1024 * 1024 * 1024};
      size = (value * units[s.group(2)!.toUpperCase()]!).round();
    }
  }

  return ReleaseTags(quality: quality, codec: codec, language: language, rip: rip, sizeBytes: size);
}

bool hasHindi(String? language) {
  if (language == null) return false;
  final lower = language.toLowerCase();
  return lower.contains('hindi') || lower.contains('dual') || lower.contains('multi');
}
