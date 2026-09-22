import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum QualityCap {
  auto('Auto', 0),
  p1080('1080p', 1080),
  p720('720p', 720),
  p480('480p', 480);

  const QualityCap(this.label, this.maxHeight);

  final String label;
  final int maxHeight;
}

const _key = 'pref.quality_cap';

class QualityCapNotifier extends Notifier<QualityCap> {
  @override
  QualityCap build() {
    unawaited(_load());
    return QualityCap.auto;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_key);
      for (final value in QualityCap.values) {
        if (value.name == name) state = value;
      }
    } on Object {
      return;
    }
  }

  Future<void> set(QualityCap value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } on Object {
      return;
    }
  }

  void cycle(int delta) {
    const values = QualityCap.values;
    unawaited(set(values[(values.indexOf(state) + delta + values.length) % values.length]));
  }
}

final qualityCapProvider = NotifierProvider<QualityCapNotifier, QualityCap>(QualityCapNotifier.new);
