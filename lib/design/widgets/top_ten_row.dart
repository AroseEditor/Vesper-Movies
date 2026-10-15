import 'package:flutter/material.dart';

import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../colors.dart';
import '../typography.dart';
import 'poster_card.dart';

class TopTenRow extends StatelessWidget {
  const TopTenRow({
    super.key,
    required this.title,
    required this.items,
    required this.mode,
    this.onSelect,
  });

  final String title;
  final List<CatalogItem> items;
  final InputMode mode;
  final void Function(CatalogItem item)? onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final posterWidth = mode.posterWidth;
    final numberWidth = posterWidth * 0.6;
    final rowHeight = posterWidth * 1.5 + PosterCard.labelHeight(true) + 20;

    return Padding(
      padding: EdgeInsets.only(bottom: mode.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mode.gutter),
            child: Text(title, style: VesperType.sectionTitle),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: mode.gutter),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: numberWidth,
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: posterWidth * 1.05,
                              fontWeight: FontWeight.w900,
                              height: 0.78,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 3
                                ..color = VesperColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      PosterCard(
                        item: item,
                        width: posterWidth,
                        autofocus: mode.isTv && index == 0,
                        onTap: () => onSelect?.call(item),
                      ),
                    ],
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
