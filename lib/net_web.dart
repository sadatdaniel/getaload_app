/// Browsers cannot open raw TCP connections; the test is offered on Android only.
Future<bool> probeTcp(String host, int port) async => false;
