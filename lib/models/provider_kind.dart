enum ProviderKind {
  moviebox('moviebox', 'MovieBox'),
  fourkhdhub('fourkhdhub', '4KHDHub'),
  dramachi('dramachi', 'Dramachi'),
  circleftp('bdix_circleftp', 'CircleFTP'),
  dhakaflix('bdix_dhakaflix', 'DhakaFlix'),
  addons('addons', 'Addons'),
  m3u('m3u', 'Live TV');

  const ProviderKind(this.id, this.label);

  final String id;
  final String label;

  bool get isBdix => this == ProviderKind.circleftp || this == ProviderKind.dhakaflix;

  bool get isLocalNetwork => isBdix;

  static final Map<String, ProviderKind> _byId = {
    for (final kind in ProviderKind.values) kind.id: kind,
  };

  static final Map<String, ProviderKind> _aliases = {
    'movie_box': ProviderKind.moviebox,
    '4khdhub': ProviderKind.fourkhdhub,
    'four_k_hd_hub': ProviderKind.fourkhdhub,
    'bdix_circle_ftp': ProviderKind.circleftp,
    'circleftp': ProviderKind.circleftp,
    'bdix_dhaka_flix': ProviderKind.dhakaflix,
    'dhakaflix': ProviderKind.dhakaflix,
    'addon': ProviderKind.addons,
  };

  static ProviderKind? byId(String value) {
    final key = value.trim().toLowerCase();
    return _byId[key] ?? _aliases[key];
  }
}

class SourceCapabilities {
  const SourceCapabilities({
    this.search = true,
    this.pagination = false,
    this.series = true,
    this.subtitles = true,
    this.catalog = false,
  });

  final bool search;
  final bool pagination;
  final bool series;
  final bool subtitles;
  final bool catalog;
}
