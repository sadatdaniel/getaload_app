import 'package:getaload/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newer versions', () {
    expect(isNewer('0.2.1', '0.2.0'), isTrue);
    expect(isNewer('0.10.0', '0.9.9'), isTrue); // numbers, not text
    expect(isNewer('0.2.0', '0.2.0'), isFalse);
    expect(isNewer('0.1.9', '0.2.0'), isFalse);
    expect(isNewer('0.2.0', 'dev'), isTrue); // a local build takes any release
  });

  test('checksum of one APK', () {
    const sums = 'aaa111  getaload-0.2.0-arm64-v8a.apk\nBBB222  getaload-0.2.0-armeabi-v7a.apk\n';
    expect(checksumFor(sums, 'getaload-0.2.0-armeabi-v7a.apk'), 'bbb222');
    expect(checksumFor(sums, 'getaload-0.2.0-x86_64.apk'), '');
  });
}
