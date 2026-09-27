import 'dart:async';

import 'package:oresoftware_next_loggers/oresoftware_next_loggers.dart';

import 'diagnostics.dart';

typedef StartupTransportErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Bridges the redacted ores-startup/v1 event stream into next-loggers/v1.
///
/// The startup boundary stays usable even when a telemetry transport is down:
/// delivery failures are reported only through [onTransportError] and never
/// escape back into application startup.
final class NextLoggersStartupDiagnosticSink implements StartupDiagnosticSink {
  NextLoggersStartupDiagnosticSink({
    required this.logger,
    this.onTransportError,
  });

  final Logger logger;
  final StartupTransportErrorHandler? onTransportError;

  @override
  void write(StartupDiagnosticEvent event) {
    unawaited(_write(event));
  }

  Future<void> _write(StartupDiagnosticEvent event) async {
    try {
      final fields = event.toJson();
      final wireEvent = fields['event'] as String;
      final logEvent = switch (event.level) {
        StartupLogLevel.debug => logger.debug('flutter.startup.$wireEvent'),
        StartupLogLevel.info => logger.info('flutter.startup.$wireEvent'),
        StartupLogLevel.warning => logger.warn('flutter.startup.$wireEvent'),
        StartupLogLevel.error => logger.error('flutter.startup.$wireEvent'),
      };

      await logEvent.addFields(<String, Object?>{
        ...fields,
        'source': 'ores_otel_flutter.startup',
      }).send();
    } catch (error, stackTrace) {
      onTransportError?.call(error, stackTrace);
    }
  }
}
