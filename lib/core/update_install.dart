import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_check.dart';

enum InstallResult { started, needsPermission, openedPage, failed }

const _channel = MethodChannel('vesper/update');

bool get canInstallInApp => Platform.isAndroid || Platform.isWindows;

Future<String?> _assetFor(UpdateInfo info) async {
  if (Platform.isWindows) return 'vesper-movies-windows-x64-setup.exe';
  if (Platform.isAndroid) {
    var abi = 'arm64-v8a';
    try {
      abi = await _channel.invokeMethod<String>('abi') ?? abi;
    } on Object {
      abi = 'arm64-v8a';
    }
    if (abi == 'x86' || abi == 'x86_64') return 'vesper-movies-x86_64.apk';
    if (abi.startsWith('armeabi')) return 'vesper-movies-armeabi-v7a.apk';
    return 'vesper-movies-arm64-v8a.apk';
  }
  return null;
}

Future<InstallResult> installUpdate(
  UpdateInfo info,
  void Function(double progress) onProgress,
) async {
  final name = await _assetFor(info);
  final url = name == null ? null : info.assets[name];
  if (name == null || url == null) {
    await launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
    return InstallResult.openedPage;
  }

  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'update'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final target = p.join(dir.path, name);

  try {
    await Dio().download(
      url,
      target,
      options: Options(receiveTimeout: const Duration(minutes: 20)),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );
  } on Object {
    return InstallResult.failed;
  }

  if (Platform.isWindows) {
    try {
      await Process.start(target, ['/S'], mode: ProcessStartMode.detached);
    } on Object {
      return InstallResult.failed;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  try {
    final outcome = await _channel.invokeMethod<String>('install', {'path': target});
    return outcome == 'permission' ? InstallResult.needsPermission : InstallResult.started;
  } on Object {
    return InstallResult.failed;
  }
}
