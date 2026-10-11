// Web: the browser does TLS itself, so links are played directly.
import 'api.dart';

class LocalProxy {
  static final instance = LocalProxy();
  Future<String> wrap(String url, Server? via) async => url;
}
