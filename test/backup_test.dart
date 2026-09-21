import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/sources/addons/addon_client.dart';
import 'package:vesper_movies/storage/backup.dart';
import 'package:vesper_movies/storage/library_store.dart';

void main() {
  test('backup round trips history, favourites and addons', () {
    const contents = BackupContents(
      library: LibraryData(
        history: [
          WatchEntry(
            id: 'tt1475582',
            title: 'Sherlock',
            mediaType: MediaType.series,
            season: 2,
            episode: 3,
            positionMs: 1200,
            durationMs: 5400,
            updatedAt: 42,
          ),
        ],
        favourites: [
          CatalogItem(
            id: MediaId(ProviderKind.addons, 'tt0816692'),
            title: 'Interstellar',
            mediaType: MediaType.movie,
            year: '2014',
          ),
        ],
      ),
      addons: [InstalledAddon(manifestUrl: 'https://addon.example/manifest.json', name: 'Example')],
    );

    final restored = decodeBackup(encodeBackup(contents))!;

    expect(restored.library.history.single.key, 'tt1475582:2:3');
    expect(restored.library.history.single.positionMs, 1200);
    expect(restored.library.favourites.single.title, 'Interstellar');
    expect(restored.addons.single.manifestUrl, 'https://addon.example/manifest.json');
  });

  test('rejects files that are not vesper backups', () {
    expect(decodeBackup(utf8.encode('{"history": []}')), isNull);
    expect(decodeBackup(utf8.encode('not json')), isNull);
  });
}
