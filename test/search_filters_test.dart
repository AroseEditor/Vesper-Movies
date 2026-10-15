import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/features/search/search_page.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';

CatalogItem _item({String? year, double? rating}) => CatalogItem(
  id: const MediaId(ProviderKind.addons, 'tt1'),
  title: 'Test',
  mediaType: MediaType.movie,
  year: year,
  rating: rating,
);

void main() {
  test('year filter keeps only items in its decade', () {
    final items = [_item(year: '2022'), _item(year: '2015'), _item(year: '1999')];
    final filtered = applySearchFilters(items, YearFilter.from2020, RatingFilter.any);
    expect(filtered.map((e) => e.year), ['2022']);
  });

  test('rating filter drops items below the minimum', () {
    final items = [_item(rating: 9.1), _item(rating: 6.0), _item(rating: null)];
    final filtered = applySearchFilters(items, YearFilter.any, RatingFilter.eight);
    expect(filtered.length, 1);
    expect(filtered.first.rating, 9.1);
  });

  test('any filters return the list unchanged', () {
    final items = [_item(year: '2001'), _item(year: '2022')];
    final filtered = applySearchFilters(items, YearFilter.any, RatingFilter.any);
    expect(filtered, items);
  });
}
