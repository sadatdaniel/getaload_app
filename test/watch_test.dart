import 'package:getaload/api.dart';
import 'package:getaload/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('server user survives a save', () {
    const s = Server(url: 'https://x.test', token: 't', name: 'x', user: 'Alice', owner: true);
    final back = Server.fromJson(s.toJson());
    expect(back.user, 'Alice');
    expect(back.owner, isTrue);
    expect(Server.fromJson({'url': 'u', 'token': 't'}).user, ''); // saved before users existed
  });

  test('watch progress from other devices merges by time, and leaves with the user', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.instance;
    await s.load();
    const srv = 'https://x.test';
    await s.touchRecent(
      {'id': 'server:$srv::/a.mkv', 'title': 'a', 'url': ''},
      const Duration(minutes: 1),
      const Duration(hours: 1),
    );
    final newer = DateTime.now().millisecondsSinceEpoch + 1000;
    await s.mergeWatched(srv, [
      {'title': 'a', 'path': '/a.mkv', 'archive': '', 'pos': 600000, 'dur': 3600000, 'at': newer},
      {'title': 'b', 'path': '/b.mkv', 'archive': '', 'pos': 1000, 'dur': 3600000, 'at': 1}, // old: sorts last
    ]);
    expect(s.recent.map((r) => r['item']['title']), ['a', 'b']);
    expect(s.position('server:$srv::/a.mkv'), const Duration(minutes: 10));
    await s.mergeWatched(srv, [
      {'title': 'a', 'path': '/a.mkv', 'pos': 1, 'at': 5}, // older than what is here: ignored
    ]);
    expect(s.position('server:$srv::/a.mkv'), const Duration(minutes: 10));
    await s.forgetServer(srv);
    expect(s.recent, isEmpty);
    expect(s.position('server:$srv::/a.mkv'), isNull);
  });
}
