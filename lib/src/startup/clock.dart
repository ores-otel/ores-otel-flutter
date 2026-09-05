import 'dart:async';

/// A cancellable scheduled callback used for startup timeouts and warnings.
abstract interface class StartupScheduledCallback {
  void cancel();
}

/// Injectable wall clock and scheduler.
///
/// Product tests can provide a manual clock, so timeout and watchdog behavior
/// never needs a real sleep.
abstract interface class StartupClock {
  DateTime nowUtc();

  StartupScheduledCallback schedule(Duration delay, void Function() callback);
}

final class SystemStartupClock implements StartupClock {
  const SystemStartupClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  StartupScheduledCallback schedule(Duration delay, void Function() callback) =>
      _TimerCallback(Timer(delay, callback));
}

final class _TimerCallback implements StartupScheduledCallback {
  _TimerCallback(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
