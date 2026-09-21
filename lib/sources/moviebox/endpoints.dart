abstract final class MovieBoxEndpoints {
  static const _base = '/wefeed-mobile-bff';

  static const visitorLogin = '$_base/user-api/visitor-login';

  static const search = '$_base/subject-api/search/v2';

  static String details(String subjectId) => '$_base/subject-api/get?subjectId=$subjectId';

  static String seasonInfo(String subjectId) =>
      '$_base/subject-api/season-info?subjectId=$subjectId';

  static String playInfo(String subjectId, {int season = 0, int episode = 0}) {
    final path = '$_base/subject-api/play-info/v2?subjectId=$subjectId';
    if (season == 0 && episode == 0) return path;
    return '$path&se=$season&ep=$episode';
  }

  static String resource(
    String subjectId, {
    int season = 0,
    int episode = 0,
    int page = 1,
    int perPage = 20,
    int resolution = 0,
  }) {
    final buffer = StringBuffer('$_base/subject-api/resource?subjectId=$subjectId');
    if (season != 0 || episode != 0) {
      buffer.write('&se=$season&ep=$episode');
    }
    buffer.write('&page=$page&perPage=$perPage');
    if (resolution != 0) {
      buffer.write('&resolution=$resolution');
    }
    return buffer.toString();
  }

  static String captions(String subjectId, String resourceId) =>
      '$_base/subject-api/get-ext-captions?subjectId=$subjectId&resourceId=$resourceId';

  static String homepage(String tabId, int page) =>
      '$_base/tab-operating?page=$page&tabId=$tabId&version=';

  static Map<String, dynamic> searchBody(String query, int page) => {
    'keyword': query,
    'page': page,
    'perPage': 15,
    'subjectType': 0,
  };

  static int pageForEpisode(int episode) => episode > 0 ? ((episode - 1) ~/ 20) + 1 : 1;
}
