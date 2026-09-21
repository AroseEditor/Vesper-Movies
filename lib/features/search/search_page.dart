import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/typography.dart';
import '../../design/widgets/poster_card.dart';
import '../../design/widgets/shimmer.dart';
import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../details/details_controller.dart';
import '../details/details_page.dart';

class SearchTextNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    if (state != value) state = value;
  }
}

final searchTextProvider = NotifierProvider<SearchTextNotifier, String>(SearchTextNotifier.new);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(searchTextProvider.notifier).set(value);
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    ref.read(searchTextProvider.notifier).set(value);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final query = ref.watch(searchTextProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 16, mode.gutter, 12),
            child: _SearchField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _submit,
              tv: mode.isTv,
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchIdle()
                : _SearchResults(query: query, mode: mode),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.tv,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VesperColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VesperColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(VesperIcons.search, size: 22, color: VesperColors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                autofocus: !tv,
                textInputAction: TextInputAction.search,
                style: VesperType.bodyStrong.copyWith(fontSize: tv ? 19 : 16),
                cursorColor: VesperColors.accent,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  hintText: 'Search films and series',
                  hintStyle: VesperType.body.copyWith(color: VesperColors.textTertiary),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  controller.clear();
                  onSubmitted('');
                },
                icon: const Icon(VesperIcons.close, size: 19),
                color: VesperColors.textTertiary,
                tooltip: 'Clear',
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchIdle extends StatelessWidget {
  const _SearchIdle();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(VesperIcons.search, size: 40, color: VesperColors.textTertiary),
          SizedBox(height: 14),
          Text('Search every source at once', style: VesperType.sectionTitle),
          SizedBox(height: 6),
          Text('Type a title to begin.', style: VesperType.body),
        ],
      ),
    );
  }
}

final titleSearchProvider = FutureProvider.autoDispose.family<List<CatalogItem>, String>((
  ref,
  query,
) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  return ref
      .read(cinemetaProvider)
      .search(query, cancel: cancel)
      .timeout(const Duration(seconds: 20));
});

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.mode});

  final String query;
  final InputMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(titleSearchProvider(query.trim()));

    return results.when(
      loading: () => _ResultsSkeleton(mode: mode),
      error: (error, stack) => const _ResultsEmpty(
        title: 'Search failed',
        message: 'The catalogue did not answer. Check your connection.',
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _ResultsEmpty(title: 'Nothing found', message: 'No match for that title.');
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(mode.gutter, 4, mode.gutter, mode.isTouch ? 108 : 32),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: mode.posterWidth + 24,
                  childAspectRatio: 2 / 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => PosterCard(
                  item: items[index],
                  width: mode.posterWidth,
                  autofocus: mode.isTv && index == 0,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (context) => DetailsPage(item: items[index])),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton({required this.mode});

  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(mode.gutter, 4, mode.gutter, 32),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: mode.posterWidth + 24,
        childAspectRatio: 2 / 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
      ),
      itemCount: 12,
      itemBuilder: (context, index) =>
          Shimmer(width: mode.posterWidth, height: mode.posterWidth * 1.5),
    );
  }
}

class _ResultsEmpty extends StatelessWidget {
  const _ResultsEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.empty, size: 40, color: VesperColors.textTertiary),
            const SizedBox(height: 14),
            Text(title, style: VesperType.sectionTitle),
            const SizedBox(height: 6),
            Text(message, style: VesperType.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
