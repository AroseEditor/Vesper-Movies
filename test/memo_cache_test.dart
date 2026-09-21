import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/memo_cache.dart';

void main() {
  test('resolve completes and does not wait on itself', () async {
    final cache = MemoCache<String, int>();

    final value = await cache.resolve('k', () async => 7).timeout(const Duration(seconds: 5));

    expect(value, 7);
  });

  test('resolve serves the cached value on a second call', () async {
    final cache = MemoCache<String, int>();
    var calls = 0;

    await cache.resolve('k', () async {
      calls++;
      return 1;
    });
    final second = await cache.resolve('k', () async {
      calls++;
      return 2;
    });

    expect(second, 1);
    expect(calls, 1);
  });

  test('resolve shares one load between concurrent callers', () async {
    final cache = MemoCache<String, int>();
    var calls = 0;

    Future<int> load() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 5;
    }

    final results = await Future.wait([
      cache.resolve('k', load),
      cache.resolve('k', load),
      cache.resolve('k', load),
    ]).timeout(const Duration(seconds: 5));

    expect(results, [5, 5, 5]);
    expect(calls, 1);
  });

  test('a failed load is not cached and does not wedge the key', () async {
    final cache = MemoCache<String, int>();

    await expectLater(cache.resolve('k', () async => throw StateError('boom')), throwsStateError);

    final value = await cache.resolve('k', () async => 3).timeout(const Duration(seconds: 5));

    expect(value, 3);
  });

  test('an expired entry is dropped', () async {
    final cache = MemoCache<String, int>(ttl: Duration.zero);
    cache.put('k', 1);
    expect(cache.peek('k'), isNull);
  });
}
