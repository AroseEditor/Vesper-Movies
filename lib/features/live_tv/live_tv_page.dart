import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../player/player_page.dart';

class PlaylistStore {
  const PlaylistStore();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'playlists.json'));
  }

  Future<List<String>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];
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
  Future<List<String>> build() => const PlaylistStore().load();

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

class LiveTvPage extends ConsumerStatefulWidget {
  const LiveTvPage({super.key});

  @override
  ConsumerState<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends ConsumerState<LiveTvPage> {
  String? _group;
  String _query = '';

  Future<void> _play(Channel channel) async {
    final navigator = Navigator.of(context);
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
