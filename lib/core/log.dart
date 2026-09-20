import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'redact.dart';

enum LogLevel { debug, info, warn, error }

class Logger {
  const Logger();

  LogLevel get threshold => kReleaseMode ? LogLevel.warn : LogLevel.info;

  void debug(String message, {String? url, String? path}) =>
      _emit(LogLevel.debug, message, url: url, path: path);

  void info(String message, {String? url, String? path}) =>
      _emit(LogLevel.info, message, url: url, path: path);

  void warn(String message, {String? url, String? path}) =>
      _emit(LogLevel.warn, message, url: url, path: path);

  void error(String message, {String? url, String? path, Object? cause}) => _emit(
    LogLevel.error,
    cause == null ? message : '$message: ${describeCause(cause)}',
    url: url,
    path: path,
  );

  void _emit(LogLevel level, String message, {String? url, String? path}) {
    if (level.index < threshold.index) return;

    final buffer = StringBuffer(message);
    if (url != null) buffer.write(' [${redactUrl(url)}]');
    if (path != null) buffer.write(' [${redactPath(path)}]');

    developer.log(buffer.toString(), name: 'vesper', level: _severity(level));
  }

  int _severity(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warn => 900,
    LogLevel.error => 1000,
  };
}

String describeCause(Object cause) {
  final text = cause.toString();
  if (!text.contains('://')) return text;
  return text.replaceAllMapped(
    RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s,)\]}"]+'),
    (match) => redactUrl(match.group(0)!),
  );
}

const log = Logger();
