import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/src/api/models.dart';
import 'package:ores_otel_flutter/src/connection_log.dart';

void main() {
  test('duplicate connection and log-level snapshots collapse', () async {
    const seed = ConnectionLogSnapshot(
      connected: false,
      endpoint: 'https://otel.example',
      logLevel: OtelLogLevel.info,
    );
    final bus = ConnectionLogBus(seed: seed);
    final seen = <ConnectionLogSnapshot>[];
    final sub = bus.snapshots.listen(seen.add);
    await Future<void>.delayed(Duration.zero);

    bus.publish(seed);
    bus.publish(
      const ConnectionLogSnapshot(
        connected: false,
        endpoint: 'https://otel.example',
        logLevel: OtelLogLevel.info,
      ),
    );
    bus.publish(
      const ConnectionLogSnapshot(
        connected: true,
        endpoint: 'https://otel.example',
        logLevel: OtelLogLevel.warn,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(seen, const [
      seed,
      ConnectionLogSnapshot(
        connected: true,
        endpoint: 'https://otel.example',
        logLevel: OtelLogLevel.warn,
      ),
    ]);
    await sub.cancel();
    bus.close();
  });
}
