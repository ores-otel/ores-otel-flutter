import 'models.dart';

/// Injectable read-only HTTP request boundary, shared by Flutter mobile/web
/// without importing dart:io or bundling a transport implementation.
typedef HealthGet = Future<int?> Function(Uri url);

class ApiClient {
  const ApiClient({required this.baseUrl});
  final String baseUrl;

  /// A passive snapshot makes no assumptions about network connectivity.
  ConnectionStatus snapshot() =>
      ConnectionStatus(connected: false, endpoint: baseUrl);

  /// Executes one explicitly injected GET /health with a bounded deadline.
  ///
  /// The caller owns network credentials, redirect policy and the HTTP
  /// implementation. On malformed configuration, timeout, or transport
  /// failure, the result remains disconnected without leaking error details.
  Future<ConnectionStatus> probe({
    required HealthGet get,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final origin = _healthUrl(baseUrl);
    if (origin == null ||
        timeout < const Duration(milliseconds: 100) ||
        timeout > const Duration(seconds: 10)) {
      return snapshot();
    }

    try {
      final status = await get(origin).timeout(timeout);
      return ConnectionStatus(connected: status == 200, endpoint: baseUrl);
    } catch (_) {
      return snapshot();
    }
  }

  static Uri? _healthUrl(String raw) {
    if (raw.isEmpty || raw.length > 2048) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final local = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      return null;
    }
    return uri.replace(path: '/health');
  }
}
