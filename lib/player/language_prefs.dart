import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _audioKey = 'pref.audio';
const _subtitleKey = 'pref.subtitle';
const _subtitlesOffKey = 'pref.subtitles_off';

const _aliases = {
  'en': 'en',
  'eng': 'en',
  'english': 'en',
  'hi': 'hi',
  'hin': 'hi',
  'hindi': 'hi',
  'ta': 'ta',
  'tam': 'ta',
  'tamil': 'ta',
  'te': 'te',
  'tel': 'te',
  'telugu': 'te',
  'ml': 'ml',
  'mal': 'ml',
  'malayalam': 'ml',
  'kn': 'kn',
  'kan': 'kn',
  'kannada': 'kn',
  'bn': 'bn',
  'ben': 'bn',
  'bengali': 'bn',
  'bangla': 'bn',
  'mr': 'mr',
  'mar': 'mr',
  'marathi': 'mr',
  'pa': 'pa',
  'pan': 'pa',
  'punjabi': 'pa',
  'ur': 'ur',
  'urd': 'ur',
  'urdu': 'ur',
  'es': 'es',
  'spa': 'es',
  'spanish': 'es',
  'espanol': 'es',
  'fr': 'fr',
  'fre': 'fr',
  'fra': 'fr',
  'french': 'fr',
  'de': 'de',
  'ger': 'de',
  'deu': 'de',
  'german': 'de',
  'it': 'it',
  'ita': 'it',
  'italian': 'it',
  'pt': 'pt',
  'por': 'pt',
  'portuguese': 'pt',
  'ru': 'ru',
  'rus': 'ru',
  'russian': 'ru',
  'ja': 'ja',
  'jpn': 'ja',
  'japanese': 'ja',
  'ko': 'ko',
  'kor': 'ko',
  'korean': 'ko',
  'zh': 'zh',
  'chi': 'zh',
  'zho': 'zh',
  'chinese': 'zh',
  'mandarin': 'zh',
  'ar': 'ar',
  'ara': 'ar',
  'arabic': 'ar',
  'tr': 'tr',
  'tur': 'tr',
  'turkish': 'tr',
  'id': 'id',
  'ind': 'id',
  'indonesian': 'id',
  'th': 'th',
  'tha': 'th',
  'thai': 'th',
  'vi': 'vi',
  'vie': 'vi',
  'vietnamese': 'vi',
};

String? languageKey(String? language, [String? title]) {
  for (final raw in [language, title]) {
    if (raw == null) continue;
    final cleaned = raw.toLowerCase().trim();
    if (cleaned.isEmpty || cleaned == 'und' || cleaned == 'unknown') continue;

    final direct = _aliases[cleaned];
    if (direct != null) return direct;

    for (final word in cleaned.split(RegExp(r'[^a-z]+'))) {
      final hit = _aliases[word];
      if (hit != null && word.length > 2) return hit;
    }
  }
  return null;
}

class LanguagePrefs {
  const LanguagePrefs({this.audio, this.subtitle, this.subtitlesOff = false});

  final String? audio;
  final String? subtitle;
  final bool subtitlesOff;

  static const empty = LanguagePrefs();
}

class LanguagePrefsNotifier extends Notifier<LanguagePrefs> {
  @override
  LanguagePrefs build() {
    unawaited(_load());
    return LanguagePrefs.empty;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = LanguagePrefs(
        audio: prefs.getString(_audioKey),
        subtitle: prefs.getString(_subtitleKey),
        subtitlesOff: prefs.getBool(_subtitlesOffKey) ?? false,
      );
    } on Object {
      return;
    }
  }

  Future<void> rememberAudio(String? key) async {
    if (key == null) return;
    state = LanguagePrefs(audio: key, subtitle: state.subtitle, subtitlesOff: state.subtitlesOff);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_audioKey, key);
    } on Object {
      return;
    }
  }

  Future<void> rememberSubtitle(String? key) async {
    state = LanguagePrefs(
      audio: state.audio,
      subtitle: key ?? state.subtitle,
      subtitlesOff: key == null,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (key != null) await prefs.setString(_subtitleKey, key);
      await prefs.setBool(_subtitlesOffKey, key == null);
    } on Object {
      return;
    }
  }
}

final languagePrefsProvider = NotifierProvider<LanguagePrefsNotifier, LanguagePrefs>(
  LanguagePrefsNotifier.new,
);
