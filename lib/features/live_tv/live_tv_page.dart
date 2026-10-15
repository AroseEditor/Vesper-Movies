import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/log.dart';
import '../../core/redact.dart';
import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../shell/input_mode.dart';
import '../../sources/m3u/m3u_parser.dart';
import '../../sources/youtube/youtube_highlights.dart';
import '../player/player_page.dart';

const defaultPlaylistSource = 'https://iptv-org.github.io/iptv/categories/sports.m3u';

class PlaylistStore {
  const PlaylistStore();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'playlists.json'));
  }

  Future<List<String>?> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded.whereType<String>().where((e) => e.trim().isNotEmpty).toList();
    } on Object catch (_) {
      return const [];
    }
  }

  Future<void> save(List<String> sources) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(sources), flush: true);
    } on Object catch (_) {
      return;
    }
  }
}

class PlaylistsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final loaded = await const PlaylistStore().load();
    if (loaded != null) return loaded;

    const seeded = [defaultPlaylistSource];
    await const PlaylistStore().save(seeded);
    return seeded;
  }

  Future<void> add(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return;

    final current = state.value ?? const <String>[];
    if (current.contains(trimmed)) return;

    final next = [...current, trimmed];
    state = AsyncValue.data(next);
    await const PlaylistStore().save(next);
    ref.invalidate(channelsProvider);
  }

  Future<void> remove(String source) async {
    final current = state.value ?? const <String>[];
    final next = current.where((e) => e != source).toList();
    state = AsyncValue.data(next);
    await const PlaylistStore().save(next);
    ref.invalidate(channelsProvider);
  }
}

final playlistsProvider = AsyncNotifierProvider<PlaylistsNotifier, List<String>>(
  PlaylistsNotifier.new,
);

final channelsProvider = FutureProvider.autoDispose<List<Channel>>((ref) async {
  final sources = ref.watch(playlistsProvider).value ?? const <String>[];
  if (sources.isEmpty) return const [];

  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 40),
      responseType: ResponseType.plain,
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  final all = <Channel>[];
  final seen = <String>{};

  for (final source in sources) {
    try {
      final String body;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        final response = await dio.get<dynamic>(source, cancelToken: cancel);
        body = '${response.data}';
      } else {
        final file = File(source);
        if (!file.existsSync()) continue;
        if (await file.length() > maxPlaylistBytes) continue;
        body = await file.readAsString();
      }

      for (final channel in parseM3u(body)) {
        if (seen.add(channel.url)) all.add(channel);
      }
    } on Object catch (error) {
      log.warn('playlist failed: ${describeCause(error)} ${describePlaylist(all.length)}');
      continue;
    }
  }

  return all;
});

final highlightSearchProvider = FutureProvider.autoDispose.family<List<HighlightResult>, String>((
  ref,
  query,
) {
  return searchHighlights(query).timeout(const Duration(seconds: 20), onTimeout: () => const []);
});

enum LiveTvTab { channels, highlights }

class LiveTvPage extends ConsumerStatefulWidget {
  const LiveTvPage({super.key});

  @override
  ConsumerState<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends ConsumerState<LiveTvPage> {
  String? _group;
  String _query = '';
  LiveTvTab _tab = LiveTvTab.channels;
  String _highlightQuery = '';
  Timer? _highlightDebounce;
  bool _resolvingHighlight = false;

  @override
  void dispose() {
    _highlightDebounce?.cancel();
    super.dispose();
  }

  void _onHighlightQueryChanged(String value) {
    _highlightDebounce?.cancel();
    _highlightDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _highlightQuery = value);
    });
  }

  Future<void> _playHighlight(HighlightResult result) async {
    if (_resolvingHighlight) return;
    setState(() => _resolvingHighlight = true);

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(playerControllerProvider.notifier);

    try {
      final url = await resolveHighlightStream(result.videoId);
      if (!mounted) return;
      if (url == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('That video would not play.'),
            backgroundColor: VesperColors.surfaceRaised,
          ),
        );
        return;
      }

      await controller.load(
        PlaybackTarget(
          source: PlaybackSource(kind: ProviderKind.youtube, url: url, sourceLabel: 'YouTube'),
          title: result.title,
          subtitle: result.channel,
        ),
      );
      await navigator.push(MaterialPageRoute<void>(builder: (context) => const PlayerPage()));
      await controller.stop();
    } on Object catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That video would not play.'),
          backgroundColor: VesperColors.surfaceRaised,
        ),
      );
    } finally {
      if (mounted) setState(() => _resolvingHighlight = false);
    }
  }

  Future<void> _play(Channel channel) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(playerControllerProvider.notifier);

    try {
      await controller.load(
        PlaybackTarget(
          source: PlaybackSource(
            kind: ProviderKind.m3u,
            url: channel.url,
            sourceLabel: channel.group ?? 'Live TV',
          ),
          title: channel.name,
          subtitle: channel.group,
        ),
      );
      await navigator.push(MaterialPageRoute<void>(builder: (context) => const PlayerPage()));
      await controller.stop();
    } on Object catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That channel would not start.'),
          backgroundColor: VesperColors.surfaceRaised,
        ),
      );
    }
  }

  Future<void> _addPlaylist() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: VesperColors.surface,
        title: const Text('Add playlist', style: VesperType.sectionTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: VesperType.body.copyWith(color: VesperColors.textPrimary),
          cursorColor: VesperColors.accent,
          decoration: const InputDecoration(
            hintText: 'M3U URL or file path',
            hintStyle: VesperType.meta,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: VesperColors.divider),
            ),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VesperColors.accent)),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: VesperType.label),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Add', style: VesperType.label.copyWith(color: VesperColors.accent)),
          ),
        ],
      ),
    );

    if (source != null && source.trim().isNotEmpty) {
      await ref.read(playlistsProvider.notifier).add(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final playlists = ref.watch(playlistsProvider).value ?? const <String>[];
    final channels = ref.watch(channelsProvider);

    if (playlists.isEmpty) {
      return _NoPlaylists(onAdd: _addPlaylist);
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 16, mode.gutter, 10),
            child: Row(
              children: [
                const Text('Live TV', style: VesperType.sectionTitle),
                const Spacer(),
                FocusableItem(
                  onActivate: _addPlaylist,
                  borderRadius: 16,
                  scaleOnFocus: false,
                  semanticLabel: 'Add playlist',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: VesperColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(VesperIcons.add, size: 17, color: VesperColors.accent),
                        SizedBox(width: 6),
                        Text('Playlist', style: VesperType.label),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 0, mode.gutter, 10),
            child: Row(
              children: [
                _TabChip(
                  label: 'Channels',
                  selected: _tab == LiveTvTab.channels,
                  onTap: () => setState(() => _tab = LiveTvTab.channels),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'Match highlights',
                  selected: _tab == LiveTvTab.highlights,
                  onTap: () => setState(() => _tab = LiveTvTab.highlights),
                ),
              ],
            ),
          ),
          if (_tab == LiveTvTab.highlights) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: mode.gutter),
              child: TextField(
                onChanged: _onHighlightQueryChanged,
                style: VesperType.body.copyWith(color: VesperColors.textPrimary),
                cursorColor: VesperColors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: VesperColors.surface,
                  prefixIcon: const Icon(VesperIcons.search, size: 19),
                  hintText: 'e.g. Barcelona vs Real Madrid 2025',
                  hintStyle: VesperType.meta,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _highlightQuery.trim().isEmpty
                  ? const _TvMessage(message: 'Search for a match to find highlights on YouTube.')
                  : _HighlightsBody(
                      query: _highlightQuery,
                      mode: mode,
                      resolving: _resolvingHighlight,
                      onPlay: _playHighlight,
                    ),
            ),
          ] else ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: mode.gutter),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                style: VesperType.body.copyWith(color: VesperColors.textPrimary),
                cursorColor: VesperColors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: VesperColors.surface,
                  prefixIcon: const Icon(VesperIcons.search, size: 19),
                  hintText: 'Filter channels',
                  hintStyle: VesperType.meta,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: channels.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: VesperColors.accent, strokeWidth: 3),
                ),
                error: (error, stack) => const _TvMessage(message: 'That playlist would not load.'),
                data: (items) {
                  if (items.isEmpty) {
                    return const _TvMessage(message: 'No channels found in that playlist.');
                  }

                  final groups = groupsOf(items);
                  final visible = filterChannels(items, group: _group, query: _query);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (groups.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(horizontal: mode.gutter),
                            itemCount: groups.length + 1,
                            separatorBuilder: (context, index) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final label = index == 0 ? 'All' : groups[index - 1];
                              final value = index == 0 ? null : groups[index - 1];
                              final selected = _group == value;

                              return FocusableItem(
                                onActivate: () => setState(() => _group = value),
                                borderRadius: 17,
                                scaleOnFocus: false,
                                semanticLabel: label,
                                child: AnimatedContainer(
                                  duration: VesperMotion.fast,
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selected ? VesperColors.accent : VesperColors.surface,
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Text(
                                    label,
                                    style: VesperType.label.copyWith(
                                      color: selected
                                          ? VesperColors.canvas
                                          : VesperColors.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            mode.gutter,
                            0,
                            mode.gutter,
                            mode.isTouch ? 110 : 30,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final channel = visible[index];
                            return _ChannelTile(
                              channel: channel,
                              autofocus: mode.isTv && index == 0,
                              onPlay: () => _play(channel),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      borderRadius: 17,
      scaleOnFocus: false,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: VesperMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? VesperColors.accent : VesperColors.surface,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: VesperType.label.copyWith(
            color: selected ? VesperColors.canvas : VesperColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HighlightsBody extends ConsumerWidget {
  const _HighlightsBody({
    required this.query,
    required this.mode,
    required this.resolving,
    required this.onPlay,
  });

  final String query;
  final InputMode mode;
  final bool resolving;
  final void Function(HighlightResult result) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(highlightSearchProvider(query.trim()));

    return results.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: VesperColors.accent, strokeWidth: 3),
      ),
      error: (error, stack) =>
          const _TvMessage(message: 'That search did not work. Check your connection.'),
      data: (items) {
        if (items.isEmpty) {
          return const _TvMessage(message: 'No highlights found for that search.');
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(mode.gutter, 0, mode.gutter, mode.isTouch ? 110 : 30),
          itemCount: items.length,
          itemBuilder: (context, index) => _HighlightTile(
            result: items[index],
            autofocus: mode.isTv && index == 0,
            disabled: resolving,
            onPlay: () => onPlay(items[index]),
          ),
        );
      },
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.result,
    required this.onPlay,
    this.autofocus = false,
    this.disabled = false,
  });

  final HighlightResult result;
  final VoidCallback onPlay;
  final bool autofocus;
  final bool disabled;

  String _duration(Duration? value) {
    if (value == null) return '';
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FocusableItem(
        onActivate: disabled ? null : onPlay,
        autofocus: autofocus,
        borderRadius: 8,
        scaleOnFocus: false,
        semanticLabel: result.title,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: result.thumbnailUrl,
                  width: 96,
                  height: 54,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(width: 96, height: 54, color: VesperColors.surface),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      style: VesperType.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        result.channel,
                        _duration(result.duration),
                      ].where((e) => e.isNotEmpty).join('  ·  '),
                      style: VesperType.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (disabled)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: VesperColors.accent),
                )
              else
                const Icon(VesperIcons.play, size: 22, color: VesperColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onPlay, this.autofocus = false});

  final Channel channel;
  final VoidCallback onPlay;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FocusableItem(
        onActivate: onPlay,
        autofocus: autofocus,
        borderRadius: 8,
        scaleOnFocus: false,
        semanticLabel: channel.name,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              const Icon(VesperIcons.liveTv, size: 21, color: VesperColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      style: VesperType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (channel.group != null && channel.group!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        channel.group!,
                        style: VesperType.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(VesperIcons.play, size: 22, color: VesperColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoPlaylists extends StatelessWidget {
  const _NoPlaylists({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.liveTv, size: 44, color: VesperColors.textTertiary),
            const SizedBox(height: 14),
            const Text('No playlists yet', style: VesperType.sectionTitle),
            const SizedBox(height: 7),
            const Text(
              'Add an M3U playlist URL to browse and stream live channels.',
              style: VesperType.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FocusableItem(
              onActivate: onAdd,
              autofocus: true,
              borderRadius: 6,
              scaleOnFocus: false,
              semanticLabel: 'Add playlist',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: VesperColors.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('Add playlist', style: VesperType.button),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvMessage extends StatelessWidget {
  const _TvMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.warning, size: 38, color: VesperColors.textTertiary),
            const SizedBox(height: 12),
            Text(message, style: VesperType.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
