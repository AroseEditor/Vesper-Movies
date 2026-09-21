import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/m3u/m3u_parser.dart';

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbc1.uk" tvg-logo="https://logo/bbc.png" group-title="News",BBC One
https://stream.example/bbc1.m3u8
#EXTINF:-1 group-title="Sport",Sky Sports, Main Event
https://stream.example/sky.m3u8
#EXTINF:-1,No Attributes Channel
https://stream.example/plain.m3u8
#EXTINF:-1 group-title="News",Duplicate
https://stream.example/bbc1.m3u8
''';

void main() {
  group('parsing', () {
    test('reads name, url, group and logo', () {
      final channels = parseM3u(_playlist);

      expect(channels, hasLength(3));
      expect(channels.first.name, 'BBC One');
      expect(channels.first.url, 'https://stream.example/bbc1.m3u8');
      expect(channels.first.group, 'News');
      expect(channels.first.logoUrl, 'https://logo/bbc.png');
      expect(channels.first.id, 'bbc1.uk');
    });

    test('keeps commas that belong to the channel name', () {
      final channels = parseM3u(_playlist);
      expect(channels[1].name, 'Sky Sports, Main Event');
      expect(channels[1].group, 'Sport');
    });

    test('accepts an entry with no attributes', () {
      final channels = parseM3u(_playlist);
      expect(channels[2].name, 'No Attributes Channel');
      expect(channels[2].group, isNull);
    });

    test('drops duplicate stream urls', () {
      final urls = parseM3u(_playlist).map((c) => c.url).toList();
      expect(urls.toSet(), hasLength(urls.length));
    });

    test('survives empty and comment only input', () {
      expect(parseM3u(''), isEmpty);
      expect(parseM3u('#EXTM3U\n# a comment\n'), isEmpty);
    });

    test('ignores a url with no preceding info line', () {
      expect(parseM3u('#EXTM3U\nhttps://orphan.example/x.m3u8\n'), isEmpty);
    });
  });

  group('attributes', () {
    test('parse quoted values containing spaces and commas', () {
      final attributes = parseAttributes(
        '#EXTINF:-1 tvg-name="Big, Bold" group-title="A B"',
      );
      expect(attributes['tvg-name'], 'Big, Bold');
      expect(attributes['group-title'], 'A B');
    });
  });

  group('grouping and filtering', () {
    test('lists groups alphabetically without blanks', () {
      expect(groupsOf(parseM3u(_playlist)), ['News', 'Sport']);
    });

    test('filters by group', () {
      final channels = parseM3u(_playlist);
      expect(filterChannels(channels, group: 'Sport'), hasLength(1));
      expect(filterChannels(channels, group: 'News'), hasLength(1));
    });

    test('filters by name or group text', () {
      final channels = parseM3u(_playlist);
      expect(filterChannels(channels, query: 'bbc'), hasLength(1));
      expect(filterChannels(channels, query: 'sport'), hasLength(1));
      expect(filterChannels(channels, query: 'nothing'), isEmpty);
    });

    test('returns everything for an empty filter', () {
      final channels = parseM3u(_playlist);
      expect(filterChannels(channels), hasLength(3));
    });
  });
}
