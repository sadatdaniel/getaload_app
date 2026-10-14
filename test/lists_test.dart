import 'package:flutter_test/flutter_test.dart';
import 'package:getaload/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved lists: per server and user, bounded, gone when another user signs in', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.instance;
    await s.load();
    await s.saveList('https://a|alice|media', [
      {'name': 'film.mkv'},
    ]);
    expect(s.savedList('https://a|alice|media')!.single['name'], 'film.mkv');
    expect(s.savedList('https://a|bob|media'), isNull);
    for (var i = 0; i < 45; i++) {
      await s.saveList('https://b|x|files|$i', []);
    }
    expect(s.savedList('https://b|x|files|0'), isNull); // the oldest went first
    expect(s.savedList('https://b|x|files|44'), isNotNull);
    await s.forgetServer('https://b');
    expect(s.savedList('https://b|x|files|44'), isNull);
  });
}
