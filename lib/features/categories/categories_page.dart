import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../design/widgets/poster_card.dart';
import '../../design/widgets/shimmer.dart';
import '../../metadata/cinemeta.dart';
import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../../sources/moviebox/adapt.dart';
import '../details/details_page.dart';

const List<String> browseGenres = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
  'Mystery',
  'Romance',
  'Sci-Fi',
  'Thriller',
  'War',
  'Western',
];

class BrowseQuery {
  const BrowseQuery({required this.type, required this.genre});

  final String type;
  final String genre;

  @override
  bool operator ==(Object other) =>
      other is BrowseQuery && other.type == type && other.genre == genre;

  @override
  int get hashCode => Object.hash(type, genre);
}

final browseProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, BrowseQuery>((ref, query) async {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final encoded = Uri.encodeComponent(query.genre);
      final url = '$cinemetaBase/catalog/${query.type}/top/genre=$encoded.json';

      final response = await dio.get<dynamic>(url, cancelToken: cancel);
      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];

      final items = <CatalogItem>[];
      for (final entry in readList(data, const ['metas'])) {
        final item = metaToCatalogItem(entry, query.type);
        if (item != null) items.add(item);
      }
      return items;
    });

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  String _type = 'movie';
  String _genre = browseGenres.first;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final results = ref.watch(
      browseProvider(BrowseQuery(type: _type, genre: _genre)),
    );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 16, mode.gutter, 10),
            child: Row(
              children: [
                const Text('Categories', style: VesperType.sectionTitle),
                const Spacer(),
                _TypeToggle(
                  type: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: mode.gutter),
              itemCount: browseGenres.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final genre = browseGenres[index];
                final selected = genre == _genre;

                return FocusableItem(
                  onActivate: () => setState(() => _genre = genre),
                  borderRadius: 17,
                  scaleOnFocus: false,
                  semanticLabel: genre,
                  child: AnimatedContainer(
                    duration: VesperMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? VesperColors.accent
                          : VesperColors.surface,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      genre,
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
          const SizedBox(height: 14),
          Expanded(
            child: results.when(
              loading: () => _BrowseSkeleton(mode: mode),
              error: (error, stack) => const _BrowseEmpty(
                message: 'That category would not load. Check your connection.',
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const _BrowseEmpty(
                    message: 'Nothing in this category right now.',
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    mode.gutter,
                    0,
                    mode.gutter,
                    mode.isTouch ? 110 : 32,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: mode.posterWidth + 24,
                    childAspectRatio: 2 / 3.55,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => PosterCard(
                    item: items[index],
                    width: mode.posterWidth,
                    autofocus: mode.isTv && index == 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => DetailsPage(item: items[index]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in const [('movie', 'Films'), ('series', 'Series')])
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FocusableItem(
              onActivate: () => onChanged(option.$1),
              borderRadius: 16,
              scaleOnFocus: false,
              semanticLabel: option.$2,
              child: AnimatedContainer(
                duration: VesperMotion.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: type == option.$1
                      ? VesperColors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: type == option.$1
                        ? VesperColors.accent
                        : VesperColors.divider,
                  ),
                ),
                child: Text(
                  option.$2,
                  style: VesperType.label.copyWith(
                    color: type == option.$1
                        ? VesperColors.textPrimary
                        : VesperColors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BrowseSkeleton extends StatelessWidget {
  const _BrowseSkeleton({required this.mode});

  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(mode.gutter, 0, mode.gutter, 32),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: mode.posterWidth + 24,
        childAspectRatio: 2 / 3.55,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
      ),
      itemCount: 12,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Shimmer(width: mode.posterWidth, height: mode.posterWidth * 1.5),
          const SizedBox(height: 8),
          Shimmer(width: mode.posterWidth * 0.7, height: 12, borderRadius: 3),
        ],
      ),
    );
  }
}

class _BrowseEmpty extends StatelessWidget {
  const _BrowseEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              VesperIcons.empty,
              size: 40,
              color: VesperColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(message, style: VesperType.body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
