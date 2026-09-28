import '../models/release.dart';

const dangerousExtensions = {
  'exe', 'msi', 'msix', 'appx', 'bat', 'cmd', 'com', 'scr', 'pif',
  'apk', 'apks', 'aab', 'ipa',
  'jar', 'vbs', 'vbe', 'js', 'jse', 'ps1', 'psm1', 'sh', 'bash', 'run',
  'deb', 'rpm', 'dmg', 'pkg', 'app', 'msu', 'reg', 'lnk', 'gadget',
};

bool isDangerousUrl(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  final clean = path.split('?').first;
  final dot = clean.lastIndexOf('.');
  if (dot < 0 || dot == clean.length - 1) return false;
  return dangerousExtensions.contains(clean.substring(dot + 1));
}

List<SubtitleOption> safeSubtitles(List<SubtitleOption> subtitles) => [
  for (final subtitle in subtitles)
    if (!isDangerousUrl(subtitle.url)) subtitle,
];
