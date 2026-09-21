import 'package:flutter/material.dart';

import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../colors.dart';
import '../icons.dart';
import '../motion.dart';
import '../typography.dart';
import 'poster_card.dart';
import 'shimmer.dart';

class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.mode,
    this.onSelect,
    this.progressOf,
    this.loading = false,
    this.autofocusFirst = false,
  });

  final String title;
  final List<CatalogItem> items;
  final InputMode mode;
  final void Function(CatalogItem item)? onSelect;
  final double? Function(CatalogItem item)? progressOf;
  final bool loading;
  final bool autofocusFirst;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final ScrollController _controller = ScrollController();
  final FocusScopeNode _scope = FocusScopeNode();

  @override
  void dispose() {
    _controller.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _nudge(int direction) {
    if (!_controller.hasClients) return;
    final width = widget.mode.posterWidth + 12;
    final target = (_controller.offset + width * 3 * direction).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(target, duration: VesperMotion.normal, curve: VesperMotion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final posterWidth = widget.mode.posterWidth;
    final rowHeight = posterWidth * 1.5 + PosterCard.labelHeight(true) + 20;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.mode.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.mode.gutter),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: VesperType.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.mode.usesPointer && widget.items.isNotEmpty) ...[
                  RowArrow(icon: VesperIcons.chevronLeft, onTap: () => _nudge(-1)),
                  const SizedBox(width: 4),
                  RowArrow(icon: VesperIcons.chevronRight, onTap: () => _nudge(1)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: rowHeight,
            child: FocusScope(
              node: _scope,
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: widget.loading ? _buildSkeleton(posterWidth) : _buildItems(posterWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(double posterWidth) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: widget.mode.gutter),
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(width: 12),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Shimmer(width: posterWidth, height: posterWidth * 1.5),
            const SizedBox(height: 8),
            Shimmer(width: posterWidth * 0.75, height: 12, borderRadius: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildItems(double posterWidth) {
    return ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: widget.mode.gutter),
      itemCount: widget.items.length,
      separatorBuilder: (context, index) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final item = widget.items[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: PosterCard(
            item: item,
            width: posterWidth,
            autofocus: widget.autofocusFirst && index == 0,
            progress: widget.progressOf?.call(item),
            onTap: () => widget.onSelect?.call(item),
          ),
        );
      },
    );
  }
}

class RowArrow extends StatelessWidget {
  const RowArrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: VesperColors.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 19, color: VesperColors.textSecondary),
      ),
    );
  }
}
