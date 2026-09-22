import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/link_source.dart';

void main() {
  test('strict title matching accepts real hits and rejects lookalikes', () {
    expect(
      strictTitle('War 2', 'War 2 (2025) NF WEB-DL Multi Audio [Hindi + Tamil]', year: '2025'),
      isTrue,
    );
    expect(strictTitle('War 2', 'Download War 2 (2025) Hindi Movie 480p', year: '2025'), isTrue);
    expect(strictTitle('War 2', 'war 2 2025 hindi hd netflix', year: '2025'), isTrue);
    expect(strictTitle('War 2', 'Beast of War (2025) Dual Audio', year: '2025'), isFalse);
    expect(
      strictTitle('War 2', 'the brink of war 2026 hindi dubbed camrip', year: '2025'),
      isFalse,
    );
    expect(strictTitle('Panchayat', 'panchayat 2020 hindi season 1 complete'), isTrue);
    expect(
      strictTitle('Batwara 1947', 'Batwara 1947 (2026) Hindi Movie HDTC', year: '2026'),
      isTrue,
    );
    expect(strictTitle('War', 'War 2 (2025) Hindi', year: '2025'), isFalse);
    expect(strictTitle('War 2', 'War 2 (2019) Hindi', year: '2025'), isFalse);
  });
}
