import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/update_check.dart';

void main() {
  test('compares release tags against the installed version', () {
    expect(compareVersions('v0.5.2', '0.5.1'), greaterThan(0));
    expect(compareVersions('0.5.1', '0.5.1+5'), 0);
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('v0.5.0', '0.5.1'), lessThan(0));
    expect(const UpdateInfo(current: '0.5.1', latest: '0.6.0', url: '').isNewer, isTrue);
  });
}
