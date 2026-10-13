import 'package:dmn_app/cookies_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cookies.txt site guess', () {
    const txt =
        '# Netscape HTTP Cookie File\n'
        '.youtube.com\tTRUE\t/\tTRUE\t0\tPREF\tx\n'
        '#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\ty\n'
        'www.youtube.com\tFALSE\t/\tTRUE\t0\tVISITOR\tz\n'
        '.google.com\tTRUE\t/\tTRUE\t0\tNID\tw\n';
    expect(guessCookieDomain(txt), 'youtube.com');
    expect(guessCookieDomain('not a cookie file'), '');
  });
}
