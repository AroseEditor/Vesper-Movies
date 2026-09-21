import 'package:dio/dio.dart';

import '../core/errors.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';
import 'content_source.dart';

class SourceMatch {
  const SourceMatch({
    required this.kind,
    required this.id,
    required this.title,
    this.score = 0,
  });

  final ProviderKind kind;
  final String id;
  final String title;
  final int score;
}

String normaliseTitle(String raw) {
  final lower = raw.toLowerCase();
  final buffer = StringBuffer();
  var lastWasSpace = true;

  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final isAlphaNumeric =
        (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x61 && rune <= 0x7a) ||
        rune > 0x7f;

    if (isAlphaNumeric) {
      buffer.write(char);
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }

  return buffer.toString().trim();
}

const Set<String> _noiseWords = {'the', 'a', 'an', 'of', 'and'};

Set<String> _tokens(String raw) {
  return normaliseTitle(raw)
      .split(' ')
      .where((w) => w.isNotEmpty && !_noiseWords.contains(w))
      .toSet();
}

int scoreCandidate({
  required String wantedTitle,
  required String? wantedYear,
  required bool wantedSeries,
  required CatalogItem candidate,
}) {
  final wanted = normaliseTitle(wantedTitle);
  final found = normaliseTitle(candidate.title);
  if (found.isEmpty) return 0;

  var score = 0;

  if (wanted == found) {
    score += 100;
  } else if (found.startsWith(wanted) || wanted.startsWith(found)) {
    score += 70;
  } else {
    final wantedTokens = _tokens(wantedTitle);
    final foundTokens = _tokens(candidate.title);
    if (wantedTokens.isEmpty || foundTokens.isEmpty) return 0;

    final shared = wantedTokens.intersection(foundTokens).length;
    if (shared == 0) return 0;

    final coverage = shared / wantedTokens.length;
    if (coverage < 0.5) return 0;
    score += (coverage * 55).round();
  }

  if (candidate.isSeries == wantedSeries) {
    score += 25;
  } else {
    score -= 60;
  }

  final year = wantedYear;
  final candidateYear = candidate.year;
  if (year != null &&
      year.isNotEmpty &&
      candidateYear != null &&
      candidateYear.isNotEmpty) {
    final a = int.tryParse(year);
    final b = int.tryParse(candidateYear);
    if (a != null && b != null) {
      final gap = (a - b).abs();
      if (gap == 0) {
        score += 25;
      } else if (gap == 1) {
        score += 10;
      } else if (gap > 3) {
        score -= 20;
      }
    }
  }

  return score;
}

class SourceMatcher {
  const SourceMatcher(this.sources);

  final Map<ProviderKind, ContentSource> sources;

  static const minimumScore = 55;

  Future<List<SourceMatch>> findAll(
    CatalogItem item, {
    CancelToken? cancel,
  }) async {
    final results = await Future.wait(
      sources.entries.map(
        (entry) => _match(entry.key, entry.value, item, cancel),
      ),
    );

    final matches = results.whereType<SourceMatch>().toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  Future<SourceMatch?> _match(
    ProviderKind kind,
    ContentSource source,
    CatalogItem item,
    CancelToken? cancel,
  ) async {
    try {
      final candidates = await source.search(item.title, cancel: cancel);
      if (candidates.isEmpty) return null;

      SourceMatch? best;
      for (final candidate in candidates) {
        final score = scoreCandidate(
          wantedTitle: item.title,
          wantedYear: item.year,
          wantedSeries: item.isSeries,
          candidate: candidate,
        );
        if (score < minimumScore) continue;
        if (best != null && score <= best.score) continue;
        best = SourceMatch(
          kind: kind,
          id: candidate.id.value,
          title: candidate.title,
          score: score,
        );
      }
      return best;
    } on Cancelled {
      rethrow;
    } on Object catch (_) {
      return null;
    }
  }
}
