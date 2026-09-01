# ores-otel-flutter

Flutter for mobile, desktop, and mobile web. No React. UI lives in `lib/src/`.

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
- structured launch events go to `dart:developer` (Android logcat) and a
  bounded memory ring buffer exposed through `StartupDiagnosticsScope`;
- `OresStartupStatusPanel` keeps timeout/failure paths usable and provides
  retry plus copyable, secret-redacted diagnostics.

Startup operations must use asynchronous I/O. CPU-heavy transformations must
run through `Isolate.run`; plugin, storage, permission, auth, migration, device,
and network work must never be awaited before the first frame. Cancellable
clients should stop when the task token fires; late results are ignored after
the phase timeout.
