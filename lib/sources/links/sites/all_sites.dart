import '../../../models/provider_kind.dart';
import '../link_source.dart';
import '../web.dart';
import 'archive_source.dart';
import 'bollyflix_source.dart';
import 'downloadhub_source.dart';
import 'filmycab_source.dart';
import 'hdhub4u_source.dart';
import 'hdmovie2_source.dart';
import 'movies4u_source.dart';
import 'moviesdrive_source.dart';
import 'moviesmod_source.dart';
import 'nfmirror_source.dart';
import 'skymovies_source.dart';
import 'topmovies_source.dart';
import 'uhdmovies_source.dart';
import 'vegamovies_source.dart';

Map<ProviderKind, LinkSource> buildLinkSources(Web web) {
  final sources = <LinkSource>[
    HdHub4uSource(web),
    VegaMoviesSource(web),
    MoviesDriveSource(web),
    BollyflixSource(web),
    Movies4uSource(web),
    HdMovie2Source(web),
    SkyMoviesSource(web),
    FilmyCabSource(web),
    UhdMoviesSource(web),
    TopMoviesSource(web),
    MoviesModSource(web),
    DownloadHubSource(web),
    ArchiveSource(web),
    NfMirrorSource(web),
  ];
  return {for (final source in sources) source.kind: source};
}
