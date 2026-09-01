import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clock.dart';
import 'diagnostics.dart';
import 'model.dart';

/// Runs independent startup dependencies concurrently after the first frame.
final class StartupCoordinator extends ChangeNotifier
    implements ValueListenable<StartupSnapshot> {
  StartupCoordinator({
    required List<StartupTask> tasks,
    required this.diagnostics,
  })  : _tasks = Map.unmodifiable({for (final task in tasks) task.name: task}),
        _phases = {
          for (final task in tasks)
            task.name: StartupPhaseSnapshot(
              name: task.name,
              dependency: task.dependency,
              critical: task.critical,
              attempt: 0,
              outcome: const StartupPhasePending(),
            ),
        } {
    if (_tasks.length != tasks.length) {
      throw ArgumentError('startup task names must be unique');
    }
    _snapshot = StartupSnapshot(
      status: StartupOverallStatus.idle,
      phases: List.unmodifiable(_phases.values),
    );
  }

  final StartupDiagnostics diagnostics;
  final Map<String, StartupTask> _tasks;
  final Map<String, StartupPhaseSnapshot> _phases;
  final Map<String, _ActiveRun> _activeRuns = {};
  late StartupSnapshot _snapshot;
  bool _disposed = false;
  bool _started = false;

  @override
  StartupSnapshot get value => _snapshot;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    diagnostics.record(StartupEvent.startupStarted);
    if (_tasks.isEmpty) {
      _recomputeSnapshot();
      diagnostics.record(StartupEvent.startupCompleted, outcome: 'ready');
      return;
    }
    _recomputeSnapshot();
    for (final task in _tasks.values) {
      unawaited(_run(task));
    }
  }

  Future<void> retry(String phaseName) async {
    if (_disposed) return;
    final task = _tasks[phaseName];
    final phase = _phases[phaseName];
    if (task == null || phase == null) {
      throw ArgumentError.value(phaseName, 'phaseName', 'unknown phase');
    }
    if (_activeRuns.containsKey(phaseName)) return;
    if (!phase.outcome.isTerminal || !phase.outcome.retryable) return;
    await _run(task);
  }

  Future<void> retryAll() async {
    if (_disposed) return;
    final retryable = _tasks.values.where((task) {
      final phase = _phases[task.name]!;
      return phase.outcome.isTerminal && phase.outcome.retryable;
    });
    await Future.wait(retryable.map(_run));
  }

  Future<void> _run(StartupTask task) async {
    if (_disposed || _activeRuns.containsKey(task.name)) return;
    final previous = _phases[task.name]!;
    final attempt = previous.attempt + 1;
    final startedAt = diagnostics.clock.nowUtc();
    final cancellation = StartupCancellationToken();
    final completion = Completer<_ExecutionResult>();
    var settled = false;

    void settle(_ExecutionResult result) {
      if (settled) return;
      settled = true;
      completion.complete(result);
    }

    final slowWarning = diagnostics.clock.schedule(task.slowWarningAfter, () {
      if (settled || _disposed) return;
      diagnostics.record(
        StartupEvent.startupPhaseSlow,
        level: StartupLogLevel.warning,
        phase: task.name,
        dependency: task.dependency,
        elapsed: diagnostics.clock.nowUtc().difference(startedAt),
        retryCount: attempt - 1,
      );
    });
    final timeout = diagnostics.clock.schedule(task.timeout, () {
      if (settled || _disposed) return;
      cancellation.cancel();
      settle(const _ExecutionTimedOut());
    });
    _activeRuns[task.name] = _ActiveRun(
      cancellation: cancellation,
      slowWarning: slowWarning,
      timeout: timeout,
      cancelRun: () => settle(const _ExecutionCancelled()),
    );
    _phases[task.name] = previous.copyWith(
      attempt: attempt,
      outcome: const StartupPhaseRunning(),
      startedAtUtc: startedAt,
      elapsed: Duration.zero,
      clearFinishedAt: true,
      clearErrorType: true,
    );
    diagnostics.record(
      StartupEvent.startupPhaseStarted,
      phase: task.name,
      dependency: task.dependency,
      retryCount: attempt - 1,
    );
    _recomputeSnapshot();

    Future<StartupTaskResult>.sync(() => task.run(cancellation)).then(
      (result) => settle(_ExecutionCompleted(result)),
      onError: (Object error, StackTrace stackTrace) {
        settle(_ExecutionThrew(error, stackTrace));
      },
    );

    final result = await completion.future;
    slowWarning.cancel();
    timeout.cancel();
    _activeRuns.remove(task.name);
    if (_disposed) return;

    final finishedAt = diagnostics.clock.nowUtc();
    final elapsed = finishedAt.difference(startedAt);
    final (outcome, error, stackTrace) = switch (result) {
      _ExecutionTimedOut() => (const StartupPhaseTimedOut(), null, null),
      _ExecutionCancelled() => (const StartupPhaseCancelled(), null, null),
      _ExecutionThrew(:final error, :final stackTrace) => (
          StartupPhaseFailed(
            reasonCode: error is StartupCancelledException
                ? 'cancelled'
                : 'unexpected_error',
            retryable: true,
          ),
          error,
          stackTrace,
        ),
      _ExecutionCompleted(:final result) => switch (result) {
          StartupTaskSucceeded() => (const StartupPhaseSucceeded(), null, null),
          StartupTaskDegraded(:final reasonCode) => (
              StartupPhaseDegraded(reasonCode),
              null,
              null,
            ),
          StartupTaskFailed(:final reasonCode, :final retryable) => (
              StartupPhaseFailed(reasonCode: reasonCode, retryable: retryable),
              null,
              null,
            ),
        },
    };
    _phases[task.name] = _phases[task.name]!.copyWith(
      outcome: outcome,
      finishedAtUtc: finishedAt,
      elapsed: elapsed,
      errorType: error?.runtimeType.toString(),
    );
    diagnostics.record(
      StartupEvent.startupPhaseCompleted,
      level: outcome is StartupPhaseFailed || outcome is StartupPhaseTimedOut
          ? StartupLogLevel.error
          : outcome is StartupPhaseDegraded
              ? StartupLogLevel.warning
              : StartupLogLevel.info,
      phase: task.name,
      dependency: task.dependency,
      outcome: outcome.code,
      elapsed: elapsed,
      retryCount: attempt - 1,
      error: error,
      stackTrace: stackTrace,
    );
    _recomputeSnapshot();
    if (_snapshot.isTerminal && _activeRuns.isEmpty) {
      diagnostics.record(
        StartupEvent.startupCompleted,
        level: _snapshot.status == StartupOverallStatus.ready
            ? StartupLogLevel.info
            : StartupLogLevel.warning,
        outcome: _snapshot.status.name,
      );
    }
  }

  void _recomputeSnapshot() {
    final phases = List<StartupPhaseSnapshot>.unmodifiable(_phases.values);
    final status = switch (phases) {
      [] => StartupOverallStatus.ready,
      _ when phases.any((phase) => !phase.outcome.isTerminal) =>
        StartupOverallStatus.running,
      _
          when phases.any(
            (phase) =>
                phase.critical &&
                (phase.outcome is StartupPhaseFailed ||
                    phase.outcome is StartupPhaseTimedOut ||
                    phase.outcome is StartupPhaseCancelled),
          ) =>
        StartupOverallStatus.failed,
      _
          when phases.any(
            (phase) =>
                phase.outcome is StartupPhaseFailed ||
                phase.outcome is StartupPhaseTimedOut ||
                phase.outcome is StartupPhaseDegraded ||
                phase.outcome is StartupPhaseCancelled,
          ) =>
        StartupOverallStatus.degraded,
      _ => StartupOverallStatus.ready,
    };
    _snapshot = StartupSnapshot(status: status, phases: phases);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final active in _activeRuns.values) {
      active.cancellation.cancel();
      active.slowWarning.cancel();
      active.timeout.cancel();
      active.cancelRun();
    }
    _activeRuns.clear();
    super.dispose();
  }
}

final class _ActiveRun {
  const _ActiveRun({
    required this.cancellation,
    required this.slowWarning,
    required this.timeout,
    required this.cancelRun,
  });

  final StartupCancellationToken cancellation;
  final StartupScheduledCallback slowWarning;
  final StartupScheduledCallback timeout;
  final void Function() cancelRun;
}

sealed class _ExecutionResult {
  const _ExecutionResult();
}

final class _ExecutionCompleted extends _ExecutionResult {
  const _ExecutionCompleted(this.result);

  final StartupTaskResult result;
}

final class _ExecutionTimedOut extends _ExecutionResult {
  const _ExecutionTimedOut();
}

final class _ExecutionCancelled extends _ExecutionResult {
  const _ExecutionCancelled();
}

final class _ExecutionThrew extends _ExecutionResult {
  const _ExecutionThrew(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
