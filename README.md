# ores-otel-flutter

Flutter for mobile, desktop, and mobile web. No React. UI lives in `lib/src/`.

## Fleet import

New Flutter applications should prefer the single public barrel:

```dart
import 'package:ores_otel_flutter/ores_otel_flutter.dart';
```

That import exposes the shared startup boundary plus the canonical
`next-loggers/v1` Dart API. Dependency resolution is declared in both
`pubspec.yaml` and `.zpkg.toml`; Zed remains the cross-repository dependency
authority while Pub resolves the concrete Dart package.

To forward startup events into the same structured logger used after launch,
pass a `NextLoggersStartupDiagnosticSink` to `runOresFlutterApp`:

```dart
final logger = Logger(appName: 'my-app');

runOresFlutterApp(
  appName: 'my-app',
  sinks: [NextLoggersStartupDiagnosticSink(logger: logger)],
  builder: (diagnostics) => MyApp(diagnostics: diagnostics),
);
```

The sink forwards only the already-redacted `ores-startup/v1` payload.
Telemetry transport failures are contained and cannot turn an otherwise usable
application launch into a startup failure.

## Responsive startup diagnostics

`package:ores_otel_flutter/startup.dart` provides the fleet startup boundary:

The emitted JSON conforms to the versioned
[`ores-startup/v1` contract](https://github.com/ores-otel/ores-interfaces/tree/main/contracts/ores-startup/v1).

- `runOresFlutterApp` installs redacted Flutter, platform, and zone error logs
  and calls `runApp` without awaiting a dependency;
- `OresStartupGate` records the first frame and lifecycle events, then starts
  independent phases concurrently after that frame;
- every `StartupTask` has a finite timeout, a cooperative cancellation token,
  a slow-phase watchdog, typed success/degraded/failure outcomes, and retry;
- structured launch events go to `dart:developer` and Flutter's Android
  logcat-visible console path, plus a bounded memory ring buffer exposed
  through `StartupDiagnosticsScope`;
- `OresStartupStatusPanel` keeps timeout/failure paths usable and provides
  retry plus copyable, secret-redacted diagnostics.

Startup operations must use asynchronous I/O. CPU-heavy transformations must
run through `Isolate.run`; plugin, storage, permission, auth, migration, device,
and network work must never be awaited before the first frame. Cancellable
clients should stop when the task token fires; late results are ignored after
the phase timeout.
