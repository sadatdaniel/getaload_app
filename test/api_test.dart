import 'dart:io';

import 'package:dmn_app/api.dart';
import 'package:dmn_app/proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pair link from dmn pair / the web panel', () {
    final s = Server.fromPairLink('dmn://pair?fp=AB00&token=dmn_x&url=https%3A%2F%2F203.0.113.5%3A8080&v=1')!;
    expect(s.url, 'https://203.0.113.5:8080');
    expect(s.token, 'dmn_x');
    expect(s.fp, 'ab00');
    expect(s.name, '203.0.113.5');
    expect(Server.fromPairLink('https://example.com'), isNull);
    expect(Server.fromPairLink('dmn://pair?url=ftp%3A%2F%2Fx&token=t'), isNull);
    expect(Server.fromPairLink('dmn://pair?url=https%3A%2F%2Fx.test'), isNull); // no token
  });

  test('typed server address', () {
    expect(Server.normalizeUrl('example.test:8080/'), 'https://example.test:8080');
    expect(Server.normalizeUrl('http://10.0.0.2:8080/x'), 'http://10.0.0.2:8080');
    expect(Server.normalizeUrl('ftp://x'), isNull);
    expect(Server.normalizeUrl(''), isNull);
    expect(Server.normalizeUrl('https:// 10.0.0.5:8080 '), 'https://10.0.0.5:8080'); // phone keyboard spaces
  });

  test('clipboard links', () {
    expect(isDownloadLink('https://example.com/a.iso'), isTrue);
    expect(isDownloadLink('magnet:?xt=urn:btih:abc'), isTrue);
    expect(isDownloadLink('hello world'), isFalse);
    expect(isDownloadLink('http://localhost'), isFalse);
    expect(isDownloadLink('https://a.com see this'), isFalse);
  });

  // Optional end-to-end check against a real server (the dev container), e.g.
  // DMN_TEST_PAIR='dmn://pair?...' flutter test
  final pair = Platform.environment['DMN_TEST_PAIR'];
  test('live server: pinned TLS, jobs, progress', () async {
    final s = Server.fromPairLink(pair!)!;
    final api = Api(s);
    expect(await api.call('GET', '/v1/health'), containsPair('status', 'ok'));
    expect(await api.jobs(), isA<List>());
    expect(await api.progress().first.timeout(const Duration(seconds: 5)), isA<List>());
    api.close();
    // A wrong pin must be refused.
    // The playback proxy: a Range request (a player seeking) comes back as 206 over the pinned connection.
    final files = await Api(s).list('/');
    final f = files.firstWhere((e) => !e.dir);
    final local = await LocalProxy.instance.wrap((await Api(s).signedUrl(f)).toString(), s);
    expect(local, startsWith('http://127.0.0.1:'));
    final req = await HttpClient().getUrl(Uri.parse(local));
    req.headers.set('range', 'bytes=1-3');
    final resp = await req.close();
    expect(resp.statusCode, 206);
    expect((await resp.fold<List<int>>([], (a, b) => a..addAll(b))).length, 3);
    final bad = Api(Server(url: s.url, token: s.token, fp: '00' * 32, name: 'x'));
    await expectLater(bad.call('GET', '/v1/health'), throwsA(isA<ApiError>()));
    bad.close();
  }, skip: pair == null ? 'set DMN_TEST_PAIR to run' : null);
}
