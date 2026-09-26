import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/startup.dart';
import 'package:oresoftware_next_loggers/oresoftware_next_loggers.dart';

void main() {
  test('forwards startup diagnostics to next-loggers without losing fields',
      () async {
    final transport = MemoryTransport();
    final logger = Logger(
      appName: 'test-app',
      console: false,
      transports: [transport],
    );
    final sink = NextLoggersStartupDiagnosticSink(logger: logger);
    final event = StartupDiagnosticEvent(
      timestampUtc: DateTime.utc(2026, 9, 26, 12),
      appName: 'test-app',
      launchId: 'launch1-1',
      event: StartupEvent.startupCompleted,
      level: StartupLogLevel.warning,
      outcome: 'degraded',
      elapsed: const Duration(milliseconds: 250),
    );

    sink.write(event);
    await Future<void>.delayed(Duration.zero);

    expect(transport.records, hasLength(1));
    final record = transport.records.single;
    expect(record.level, LogLevel.warn);
    expect(record.message, 'flutter.startup.startup_completed');
    expect(record.fields['event'], 'startup_completed');
    expect(record.fields['outcome'], 'degraded');
    expect(record.fields['elapsed_ms'], 250);
    expect(record.fields['source'], 'ores_otel_flutter.startup');
  });

  test('contains transport failures instead of breaking startup', () async {
    Object? reportedError;
    StackTrace? reportedStackTrace;
    final logger = Logger(
      appName: 'test-app',
      console: false,
      transports: [_FailingTransport()],
    );
    final sink = NextLoggersStartupDiagnosticSink(
      logger: logger,
      onTransportError: (error, stackTrace) {
        reportedError = error;
        reportedStackTrace = stackTrace;
      },
    );
    final event = StartupDiagnosticEvent(
      timestampUtc: DateTime.utc(2026, 9, 26, 12),
      appName: 'test-app',
      launchId: 'launch1-2',
      event: StartupEvent.appLaunch,
      level: StartupLogLevel.info,
    );

    sink.write(event);
    await Future<void>.delayed(Duration.zero);

    expect(reportedError, isA<StateError>());
    expect(reportedStackTrace, isNotNull);
  });
}

final class _FailingTransport implements LogTransport {
  @override
  Future<void> write(LogRecord record) async {
    throw StateError('expected test failure');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
