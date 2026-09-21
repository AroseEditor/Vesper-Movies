import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../sources/source_matcher.dart';
import '../player/player_page.dart';
import 'playback_session.dart';

Future<void> launchPlayback(
  BuildContext context, {
  required CatalogItem item,
  required String title,
  required List<SourceMatch> matches,
  List<Season> seasons = const [],
  int season = 0,
  int episode = 0,
  Release? preferred,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final root = Navigator.of(context, rootNavigator: true);
  final session = container.read(playbackSessionProvider.notifier);

  final opening = session.start(
    item: item,
    title: title,
    matches: matches,
    seasons: seasons,
    season: season,
    episode: episode,
    preferred: preferred,
  );

  await root.push(
    MaterialPageRoute<void>(builder: (context) => PlayerPage(onProgress: session.recordProgress)),
  );

  session.end();
  await container.read(playerControllerProvider.notifier).stop();
  await opening.catchError((Object _) {});
}
