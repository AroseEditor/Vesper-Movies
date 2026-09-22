import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media.dart';
import '../../models/release.dart';
import '../../player/external_player.dart';
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

  if (container.read(playerChoiceProvider) == PlayerChoice.vlc) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Finding a stream for VLC'), duration: Duration(seconds: 3)),
    );
    final label = season > 0 ? '$title S${season}E$episode' : title;
    final found = await session.resolveForExternal(
      item: item,
      title: label,
      matches: matches,
      season: season,
      episode: episode,
      preferred: preferred,
      accept: vlcCanPlay,
    );
    final opened = found != null && await openInVlc(found.$1, title: label, start: found.$2);
    if (opened) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          found == null
              ? 'No stream VLC can open was found. Playing in Vesper instead.'
              : 'VLC is not installed. Playing in Vesper instead.',
        ),
      ),
    );
  }

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
