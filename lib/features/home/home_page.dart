import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/typography.dart';
import '../../design/widgets/hero_billboard.dart';
import '../../design/widgets/media_row.dart';
import '../../design/widgets/shimmer.dart';
import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../details/details_page.dart';
import 'home_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final feed = ref.watch(homeFeedProvider);

    return feed.when(
      loading: () => _HomeSkeleton(mode: mode),
      error: (error, stack) =>
          _HomeError(mode: mode, onRetry: () => ref.read(homeFeedProvider.notifier).refresh()),
      data: (data) => _HomeContent(mode: mode, feed: data),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.mode, required this.feed});

  final InputMode mode;
  final HomeFeed feed;

  void _open(BuildContext context, CatalogItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => DetailsPage(item: item)));
  }

  @override
  Widget build(BuildContext context) {
    final spotlight = feed.spotlight;
    final bottomPad = mode.isTouch ? 108.0 : 40.0;

    return CustomScrollView(
      slivers: [
        if (spotlight != null)
          SliverToBoxAdapter(
            child: HeroBillboard(
              item: spotlight,
              mode: mode,
              description: feed.spotlightOverview,
              autofocusPlay: mode.isTv,
              onPlay: () => _open(context, spotlight),
              onInfo: () => _open(context, spotlight),
              onToggleList: () => _open(context, spotlight),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.only(top: mode.rowGap, bottom: bottomPad),
          sliver: SliverList.builder(
            itemCount: feed.shelves.length,
            itemBuilder: (context, index) {
              final shelf = feed.shelves[index];
              return MediaRow(
                title: shelf.title,
                items: shelf.items,
                mode: mode,
                onSelect: (item) => _open(context, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({required this.mode});

  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer(
            width: double.infinity,
            height: height * (mode.isTouch ? 0.62 : 0.68),
            borderRadius: 0,
          ),
          SizedBox(height: mode.rowGap),
          for (var i = 0; i < 2; i++)
            MediaRow(title: ' ', items: const [], mode: mode, loading: true),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.mode, required this.onRetry});

  final InputMode mode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: mode.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.warning, size: 42, color: VesperColors.textTertiary),
            const SizedBox(height: 14),
            const Text('Nothing loaded', style: VesperType.sectionTitle),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: VesperType.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            HeroButton(label: 'Retry', icon: VesperIcons.refresh, onTap: onRetry, filled: true),
          ],
        ),
      ),
    );
  }
}
