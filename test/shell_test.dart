import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/design/theme.dart';
import 'package:vesper_movies/design/widgets/media_row.dart';
import 'package:vesper_movies/design/widgets/poster_card.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/shell/bottom_dock.dart';
import 'package:vesper_movies/shell/destinations.dart';
import 'package:vesper_movies/shell/input_mode.dart';
import 'package:vesper_movies/shell/side_rail.dart';

CatalogItem _item(String title) => CatalogItem(
  id: MediaId(ProviderKind.moviebox, title),
  title: title,
  mediaType: MediaType.movie,
  year: '2025',
);

Widget _host(Widget child, {InputMode mode = InputMode.touch}) {
  return ProviderScope(
    child: MaterialApp(
      theme: VesperTheme.build(),
      home: InputModeScope(
        mode: mode,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('bottom dock renders every destination and reports taps', (tester) async {
    var selected = -1;

    await tester.pumpWidget(
      _host(BottomDock(currentIndex: 0, onSelect: (index) => selected = index)),
    );

    for (final destination in AppDestination.values) {
      expect(find.text(destination.label), findsOneWidget);
    }

    await tester.tap(find.text(AppDestination.search.label));
    await tester.pump();

    expect(selected, AppDestination.values.indexOf(AppDestination.search));
  });

  testWidgets('side rail starts collapsed and hides its labels', (tester) async {
    await tester.pumpWidget(
      _host(
        SideRail(currentIndex: 0, onSelect: (_) {}, mode: InputMode.tv),
        mode: InputMode.tv,
      ),
    );
    await tester.pumpAndSettle();

    final rail = tester.widget<AnimatedContainer>(
      find.descendant(of: find.byType(SideRail), matching: find.byType(AnimatedContainer)).first,
    );
    expect(rail.constraints?.maxWidth, 84.0);

    final label = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text(AppDestination.home.label),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(label.opacity, 0.0);
  });

  testWidgets('media row lays out one card per item', (tester) async {
    final items = [_item('One'), _item('Two'), _item('Three')];

    await tester.pumpWidget(
      _host(MediaRow(title: 'Trending Now', items: items, mode: InputMode.touch)),
    );
    await tester.pump();

    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.byType(PosterCard), findsNWidgets(3));
  });

  testWidgets('media row shows skeletons while loading and no cards', (tester) async {
    await tester.pumpWidget(
      _host(const MediaRow(title: 'Trending Now', items: [], mode: InputMode.touch, loading: true)),
    );
    await tester.pump();

    expect(find.byType(PosterCard), findsNothing);
  });

  testWidgets('poster falls back to a branded tile when art is missing', (tester) async {
    await tester.pumpWidget(_host(PosterCard(item: _item('Harbour Lights'), width: 120)));
    await tester.pump();

    expect(find.byType(PosterFallback), findsOneWidget);
    expect(find.text('Harbour Lights'), findsOneWidget);
  });

  testWidgets('poster shows the title and meta below the image', (tester) async {
    const item = CatalogItem(
      id: MediaId(ProviderKind.moviebox, 'tt1'),
      title: 'Harbour Lights',
      mediaType: MediaType.movie,
      year: '2025',
      rating: 7.4,
    );

    await tester.pumpWidget(_host(const PosterCard(item: item, width: 140)));
    await tester.pump();

    expect(find.text('Harbour Lights'), findsOneWidget);
    expect(find.text('2025  Film  7.4'), findsOneWidget);

    final art = tester.getRect(find.byType(PosterFallback));
    final label = tester.getRect(find.text('Harbour Lights'));
    expect(label.top, greaterThan(art.bottom - 1));
  });

  testWidgets('poster hides the title when the label is turned off', (tester) async {
    const item = CatalogItem(
      id: MediaId(ProviderKind.moviebox, 'tt2'),
      title: 'Quiet Frequency',
      mediaType: MediaType.series,
    );

    await tester.pumpWidget(_host(const PosterCard(item: item, width: 140, showLabel: false)));
    await tester.pump();

    expect(find.text('Quiet Frequency'), findsOneWidget);
    expect(find.text('Series'), findsNothing);
  });

  test('input mode drives layout affordances', () {
    expect(InputMode.touch.usesRail, isFalse);
    expect(InputMode.tv.usesRail, isTrue);
    expect(InputMode.desktop.usesRail, isTrue);
    expect(InputMode.desktop.usesPointer, isTrue);
    expect(InputMode.tv.usesPointer, isFalse);
    expect(InputMode.tv.posterWidth, greaterThan(InputMode.touch.posterWidth));
    expect(InputMode.tv.textScale, greaterThan(1.0));
  });
}
