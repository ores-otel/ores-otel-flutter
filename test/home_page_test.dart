import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/src/api/models.dart';
import 'package:ores_otel_flutter/src/app.dart';
import 'package:ores_otel_flutter/src/connection_log.dart';

void main() {
  testWidgets('home observes the connection log bus', (tester) async {
    final bus = ConnectionLogBus(
      seed: const ConnectionLogSnapshot(
        connected: false,
        endpoint: 'https://otel.example',
        logLevel: OtelLogLevel.info,
      ),
    );
    addTearDown(bus.close);

    await tester.pumpWidget(OresOtelApp(connectionLog: bus));
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('https://otel.example'), findsOneWidget);

    bus.publish(
      const ConnectionLogSnapshot(
        connected: true,
        endpoint: 'https://otel.example',
        logLevel: OtelLogLevel.info,
      ),
    );
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
  });
}
