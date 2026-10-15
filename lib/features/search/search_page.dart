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
import '../details/details_page.dart';
import '../home/home_controller.dart';

class SearchTextNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    if (state != value) state = value;
  }
}

final searchTextProvider = NotifierProvider<SearchTextNotifier, String>(SearchTextNotifier.new);

enum YearFilter {
  any('Any year', null),
  from2020('2020s', 2020),
  from2010('2010s', 2010),
  from2000('2000s', 2000),
  older('Before 2000', null);

  const YearFilter(this.label, this.from);

  final String label;
  final int? from;

  bool matches(String? year) {
    final value = int.tryParse(year ?? '');
    if (value == null) return this == YearFilter.any;
    switch (this) {
      case YearFilter.any:
        return true;
      case YearFilter.from2020:
        return value >= 2020;
      case YearFilter.from2010:
        return value >= 2010 && value < 2020;
      case YearFilter.from2000:
        return value >= 2000 && value < 2010;
      case YearFilter.older:
        return value < 2000;
    }
  }
}

enum RatingFilter {
  any('Any rating', 0),
  seven('7+', 7),
  eight('8+', 8),
  nine('9+', 9);

  const RatingFilter(this.label, this.min);

  final String label;
  final int min;

  bool matches(double? rating) => min == 0 || (rating ?? 0) >= min;
}

List<CatalogItem> applySearchFilters(
  List<CatalogItem> items,
  YearFilter year,
  RatingFilter rating,
) {
  if (year == YearFilter.any && rating == RatingFilter.any) return items;
  return items.where((item) => year.matches(item.year) && rating.matches(item.rating)).toList();
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  YearFilter _year = YearFilter.any;
  RatingFilter _rating = RatingFilter.any;

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
          if (query.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(mode.gutter, 0, mode.gutter, 12),
              child: _FilterBar(
                year: _year,
                rating: _rating,
                onYearChanged: (value) => setState(() => _year = value),
                onRatingChanged: (value) => setState(() => _rating = value),
              ),
            ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchIdle()
                : _SearchResults(query: query, mode: mode, year: _year, rating: _rating),
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.year,
    required this.rating,
    required this.onYearChanged,
    required this.onRatingChanged,
  });

  final YearFilter year;
  final RatingFilter rating;
  final ValueChanged<YearFilter> onYearChanged;
  final ValueChanged<RatingFilter> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in YearFilter.values)
            _FilterChip(
              label: option.label,
              selected: option == year,
              onTap: () => onYearChanged(option),
            ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: VesperColors.divider),
          const SizedBox(width: 12),
          for (final option in RatingFilter.values)
            _FilterChip(
              label: option.label,
              selected: option == rating,
              onTap: () => onRatingChanged(option),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? VesperColors.accent : VesperColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: VesperType.label.copyWith(
              color: selected ? VesperColors.canvas : VesperColors.textSecondary,
            ),
          ),
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
      .read(metadataServiceProvider)
      .search(query, cancel: cancel)
      .timeout(const Duration(seconds: 20));
});

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.mode,
    required this.year,
    required this.rating,
  });

  final String query;
  final InputMode mode;
  final YearFilter year;
  final RatingFilter rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(titleSearchProvider(query.trim()));

    return results.when(
      loading: () => _ResultsSkeleton(mode: mode),
      error: (error, stack) => const _ResultsEmpty(
        title: 'Search failed',
        message: 'The catalogue did not answer. Check your connection.',
      ),
      data: (fetched) {
        final items = applySearchFilters(fetched, year, rating);
        if (items.isEmpty) {
          return _ResultsEmpty(
            title: 'Nothing found',
            message: fetched.isEmpty
                ? 'No match for that title.'
                : 'No match for that title with these filters.',
          );
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
