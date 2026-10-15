import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class HighlightResult {
  const HighlightResult({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;
  final String thumbnailUrl;
}

Future<List<HighlightResult>> searchHighlights(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  final yt = YoutubeExplode();
  try {
    final results = await yt.search.search('$trimmed highlights');
    return [
      for (final video in results)
        HighlightResult(
          videoId: video.id.value,
          title: video.title,
          channel: video.author,
          duration: video.duration,
          thumbnailUrl: video.thumbnails.highResUrl,
        ),
    ];
  } on Object {
    return const [];
  } finally {
    yt.close();
  }
}

Future<String?> resolveHighlightStream(String videoId) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(VideoId(videoId));
    if (manifest.muxed.isEmpty) return null;
    return manifest.muxed.withHighestBitrate().url.toString();
  } on Object {
    return null;
  } finally {
    yt.close();
  }
}
