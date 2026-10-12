import 'dart:io';

/// Whether a TCP connection to host:port succeeds within 5 seconds (from this device).
Future<bool> probeTcp(String host, int port) async {
  try {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
