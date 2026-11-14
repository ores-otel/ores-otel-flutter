import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/src/api/client.dart';

void main() {
  test('uses an injected transport for a successful health probe', () async {
    final client = ApiClient(baseUrl: 'https://otel.example/');
    final result = await client.probe(
      get: (url) async {
        expect(url.toString(), 'https://otel.example/health');
        return 200;
      },
    );
    expect(result.connected, isTrue);
    expect(result.endpoint, 'https://otel.example/');
  });

  test('rejects unsafe URL input without calling a transport', () async {
    var calls = 0;
    for (final url in <String>[
      'http://otel.example/',
      'https://user:pass@otel.example/',
      'https://otel.example/private',
      'https://otel.example/?token=secret',
      'https://otel.example/#opaque',
    ]) {
      final status = await ApiClient(baseUrl: url).probe(
        get: (_) async {
          calls += 1;
          return 200;
        },
      );
      expect(status.connected, isFalse, reason: url);
    }
    expect(calls, 0);
  });

  test('non-200 and failing transport remain disconnected', () async {
    const client = ApiClient(baseUrl: 'https://otel.example/');
    final unhealthy = await client.probe(get: (_) async => 503);
    final failed = await client.probe(
      get: (_) async => throw StateError('bearer secret must not leak'),
    );
    expect(unhealthy.connected, isFalse);
    expect(failed.connected, isFalse);
  });

  test('invalid timeout prevents the request', () async {
    const client = ApiClient(baseUrl: 'https://otel.example/');
    var calls = 0;
    final status = await client.probe(
      timeout: Duration.zero,
      get: (_) async {
        calls += 1;
        return 200;
      },
    );
    expect(status.connected, isFalse);
    expect(calls, 0);
  });
}
