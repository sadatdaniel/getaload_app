import 'package:getaload/site_signin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android cookie headers become cookies.txt for the site and its subdomains', () {
    final txt = cookiesTxt('youtube.com', ['SID=abc; HSID=x=y', 'SID=other; LOGIN_INFO=z', '']);
    expect(txt, contains('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc\n'));
    expect(txt, contains('\tHSID\tx=y\n')); // "=" inside a value stays
    expect(txt, isNot(contains('other'))); // the first value of a name wins
    expect(txt, contains('\tLOGIN_INFO\tz\n'));
    expect(cookiesTxt('youtube.com', ['', ' ']), '');
  });
}
