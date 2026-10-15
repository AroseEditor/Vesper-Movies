import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('vesper/pip');

Future<void> setPipEnabled(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('setEnabled', enabled);
  } on Object {
    return;
  }
}
