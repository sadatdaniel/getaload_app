import 'dart:convert';

import 'package:getaload/phone_addons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const base = 'https://addon.test/cfg';
  final manifest = {
    'id': 'org.test',
    'name': 'Test add-on',
    'types': ['movie', 'series'],
    'idPrefixes': ['tt'],
    'resources': ['catalog', 'stream'],
    'catalogs': [
      {
        'type': 'movie',
        'id': 'top',
        'name': 'Top',
        'extra': [
          {'name': 'search'},
        ],
      },
      {
        'type': 'movie',
        'id': 'genre',
        'extra': [
          {'name': 'genre', 'isRequired': true},
        ],
      },
    ],
  };

  test('routing rules match the server (types, id prefixes, required extras)', () {
    expect(PhoneAddons.handles(manifest, 'stream', 'movie', 'tt123'), isTrue);
    expect(PhoneAddons.handles(manifest, 'stream', 'movie', 'kitsu:1'), isFalse);
    expect(PhoneAddons.handles(manifest, 'stream', 'channel', 'tt123'), isFalse);
    expect(PhoneAddons.handles(manifest, 'meta', 'movie', 'tt123'), isFalse);
    expect(
      PhoneAddons.handles(
        {
          'resources': [
            {
              'name': 'stream',
              'types': ['movie'],
              'idPrefixes': ['kitsu'],
            },
          ],
        },
        'stream',
        'movie',
        'kitsu:1',
      ),
      isTrue,
    );
  });

  test('the phone only fetches the add-on\'s JSON; sources come back as descriptions', () async {
    final asked = <Uri>[];
    final client = MockClient((req) async {
      asked.add(req.url);
      final p = req.url.path;
      final body = p.endsWith('/manifest.json')
          ? manifest
          : p.startsWith('/cfg/catalog/movie/top')
          ? {
              'metas': [
                {'id': 'tt1', 'type': 'movie', 'name': 'A film'},
              ],
            }
          : p == '/cfg/stream/movie/tt1.json'
          ? {
              'streams': [
                {'name': '1080p', 'infoHash': '0123456789abcdef0123456789abcdef01234567'},
              ],
            }
          : null;
      return body == null ? http.Response('nope', 404) : http.Response(jsonEncode(body), 200);
    });
    await http.runWithClient(() async {
      final addons = [PhoneAddon(base, await PhoneAddons.manifest(base))];
      final home = await PhoneAddons.catalogs(addons);
      expect(home.single['name'], 'Top'); // the genre catalog needs an extra: left out
      final found = await PhoneAddons.catalogs(addons, query: 'a film');
      expect(found.single['metas'], isNotEmpty);
      final streams = await PhoneAddons.streams(addons, 'movie', 'tt1');
      expect(streams.single['addon'], 'Test add-on');
      expect(streams.single['infoHash'], isNotNull);
    }, () => client);
    // Only HTTPS GETs of the add-on's own .json routes: no trackers, peers or anything else.
    for (final u in asked) {
      expect(u.scheme, 'https');
      expect(u.host, 'addon.test');
      expect(u.path, endsWith('.json'));
    }
    expect(asked.map((u) => u.path), contains('/cfg/catalog/movie/top/search=a+film.json'));
  });
}
