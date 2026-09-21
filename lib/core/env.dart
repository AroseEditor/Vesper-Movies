abstract final class Env {
  static const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

  static bool get hasTmdbKey => tmdbApiKey.trim().isNotEmpty;
}
