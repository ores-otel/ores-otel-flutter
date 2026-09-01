import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'clock.dart';
import 'diagnostics.dart';

typedef OresAppBuilder = Widget Function(StartupDiagnostics diagnostics);

/// Installs bounded top-level diagnostics and schedules the Flutter app without
/// awaiting any dependency.
///
/// Call this directly from `main`; do not initialize bindings, storage,
/// plugins, databases, authentication, telemetry, or networks beforehand.
void runOresFlutterApp({
  required String appName,
  required OresAppBuilder builder,
  StartupClock clock = const SystemStartupClock(),
  StartupDiagnosticBuffer? buffer,
  List<StartupDiagnosticSink> sinks = const [],
  bool emitToDeveloperLog = true,
}) {
  final diagnostics = StartupDiagnostics.create(
    appName: appName,
    clock: clock,
    buffer: buffer,
    sinks: sinks,
    emitToDeveloperLog: emitToDeveloperLog,
  );

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      final previousFlutterError = FlutterError.onError;
      FlutterError.onError = (details) {
        diagnostics.record(
          StartupEvent.uncaughtFlutterError,
          level: StartupLogLevel.error,
          error: details.exception,
          stackTrace: details.stack,
        );
        if (previousFlutterError != null) {
          previousFlutterError(details);
        } else {
          FlutterError.presentError(details);
        }
      };

      final previousPlatformError = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        diagnostics.record(
          StartupEvent.uncaughtPlatformError,
          level: StartupLogLevel.error,
          error: error,
          stackTrace: stackTrace,
        );
        return previousPlatformError?.call(error, stackTrace) ?? true;
      };

      diagnostics.record(StartupEvent.appLaunch);
      runApp(builder(diagnostics));
    },
    (error, stackTrace) {
      diagnostics.record(
        StartupEvent.uncaughtZoneError,
        level: StartupLogLevel.error,
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}
