import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/features/details/playback_session.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/models/release.dart';

Release _r(String quality) =>
    Release(kind: ProviderKind.moviebox, filename: quality, quality: quality, mirrors: const []);

void main() {
  test('phones try 1080p first, then 720p, and 4k last', () {
    final ranked = rankForPhone([_r('2160p'), _r('720p'), _r('1080p'), _r('480p'), _r('4K')]);
    expect(ranked.map((r) => r.quality), ['1080p', '720p', '480p', '2160p', '4K']);
  });

  test('a quality cap pushes anything above it to the end', () {
    final ranked = rankForDevice(
      [_r('2160p'), _r('1080p'), _r('720p'), _r('480p')],
      cap: 720,
      phone: false,
    );
    expect(ranked.map((r) => r.quality), ['720p', '480p', '2160p', '1080p']);
  });

  test('real releases beat cams and hindi comes first when preferred', () {
    const cam = Release(
      kind: ProviderKind.hdhub4u,
      filename: 'cam',
      quality: '1080p',
      rip: 'CAM',
      language: 'Hindi',
    );
    const english = Release(
      kind: ProviderKind.hdhub4u,
      filename: 'en',
      quality: '1080p',
      rip: 'WEB-DL',
      language: 'English',
    );
    const hindi = Release(
      kind: ProviderKind.hdhub4u,
      filename: 'hi',
      quality: '720p',
      rip: 'WEB-DL',
      language: 'Hindi + English',
    );
    final ranked = rankForDevice([cam, english, hindi], cap: 0, phone: false, preferHindi: true);
    expect(ranked.map((r) => r.filename), ['hi', 'en', 'cam']);
  });

  test('huge remuxes and 10 bit encodes are tried after lighter streams', () {
    const remux = Release(
      kind: ProviderKind.uhdmovies,
      filename: 'remux',
      quality: '1080p',
      rip: 'Remux',
      sizeBytes: 19 * 1024 * 1024 * 1024,
    );
    const tenBit = Release(
      kind: ProviderKind.moviesmod,
      filename: 'tenbit',
      quality: '1080p',
      codec: 'HEVC 10bit',
      sizeBytes: 500 * 1024 * 1024,
    );
    const light = Release(
      kind: ProviderKind.moviesmod,
      filename: 'light',
      quality: '720p',
      codec: 'x264',
      sizeBytes: 600 * 1024 * 1024,
    );
    final ranked = rankForDevice([remux, tenBit, light], cap: 0, phone: true);
    expect(ranked.map((r) => r.filename), ['light', 'tenbit', 'remux']);
  });

  test('downloadhub is tried after every other source', () {
    const hub = Release(kind: ProviderKind.downloadhub, filename: 'hub', quality: '1080p');
    const mod = Release(kind: ProviderKind.moviesmod, filename: 'mod', quality: '480p');
    final ranked = rankForDevice([hub, mod], cap: 0, phone: false);
    expect(ranked.map((r) => r.filename), ['mod', 'hub']);
  });

  test('sources that keep failing are tried after sources that work', () {
    const flaky = Release(kind: ProviderKind.hdhub4u, filename: 'flaky', quality: '1080p');
    const steady = Release(kind: ProviderKind.moviesmod, filename: 'steady', quality: '480p');
    final ranked = rankForDevice(
      [flaky, steady],
      cap: 0,
      phone: false,
      health: const {'hdhub4u': -3, 'moviesmod': 2},
    );
    expect(ranked.map((r) => r.filename), ['steady', 'flaky']);
  });
}
