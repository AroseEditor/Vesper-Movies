import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../shell/input_mode.dart';
import '../../storage/library_controller.dart';
import '../../storage/library_store.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final data = ref.watch(libraryProvider).value ?? const LibraryData();
    final stats = computeLibraryStats(data);

    return Scaffold(
      backgroundColor: VesperColors.canvas,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(mode.gutter, 18, mode.gutter, 40),
          children: [
            Row(
              children: [
                FocusableItem(
                  onActivate: () => Navigator.of(context).maybePop(),
                  borderRadius: 22,
                  scaleOnFocus: false,
                  semanticLabel: 'Back',
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(VesperIcons.back, size: 24),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Your stats', style: VesperType.sectionTitle),
              ],
            ),
            const SizedBox(height: 26),
            if (stats.titlesWatched == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Nothing watched yet.', style: VesperType.body),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(label: 'Hours watched', value: _hours(stats.watchTime)),
                  _StatCard(label: 'Titles watched', value: '${stats.titlesWatched}'),
                  _StatCard(label: 'Movies finished', value: '${stats.moviesCompleted}'),
                  _StatCard(label: 'Episodes finished', value: '${stats.episodesCompleted}'),
                  if (stats.longestTitle.isNotEmpty)
                    _StatCard(
                      label: 'Longest watch',
                      value: _hours(stats.longestSession),
                      detail: stats.longestTitle,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _hours(Duration value) {
    final hours = value.inMinutes / 60;
    return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)}h';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VesperColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: VesperType.sectionTitle.copyWith(color: VesperColors.accent)),
          const SizedBox(height: 6),
          Text(label, style: VesperType.body),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, style: VesperType.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
