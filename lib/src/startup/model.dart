import 'dart:async';

typedef StartupOperation =
    Future<StartupTaskResult> Function(StartupCancellationToken cancellation);

sealed class StartupTaskResult {
  const StartupTaskResult();
}

final class StartupTaskSucceeded extends StartupTaskResult {
  const StartupTaskSucceeded();
}

final class StartupTaskDegraded extends StartupTaskResult {
  StartupTaskDegraded({required this.reasonCode}) {
    _checkSafeIdentifier(reasonCode, 'reasonCode');
  }

  final String reasonCode;
}

final class StartupTaskFailed extends StartupTaskResult {
  StartupTaskFailed({required this.reasonCode, this.retryable = true}) {
    _checkSafeIdentifier(reasonCode, 'reasonCode');
  }

  final String reasonCode;
  final bool retryable;
}

/// One independent, timeout-bounded startup dependency.
///
/// [run] must use asynchronous I/O. CPU-heavy work belongs in `Isolate.run`,
/// and cancellable clients should stop when [StartupCancellationToken] fires.
final class StartupTask {
  StartupTask({
    required this.name,
    required this.dependency,
    required this.timeout,
    required this.run,
    this.slowWarningAfter = const Duration(seconds: 2),
    this.critical = false,
  }) {
    _checkSafeIdentifier(name, 'name');
    _checkSafeIdentifier(dependency, 'dependency');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (slowWarningAfter <= Duration.zero || slowWarningAfter >= timeout) {
      throw ArgumentError.value(
        slowWarningAfter,
        'slowWarningAfter',
        'must be positive and shorter than timeout',
      );
    }
  }

  final String name;
  final String dependency;
  final Duration timeout;
  final Duration slowWarningAfter;
  final bool critical;
  final StartupOperation run;
}

/// Cooperative cancellation signal owned by the startup coordinator.
final class StartupCancellationToken {
  bool _isCancelled = false;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void throwIfCancelled() {
    if (_isCancelled) throw const StartupCancelledException();
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}

final class StartupCancelledException implements Exception {
  const StartupCancelledException();
}

sealed class StartupPhaseOutcome {
  const StartupPhaseOutcome();

  bool get isTerminal;
  bool get retryable;
  String get code;
}

final class StartupPhasePending extends StartupPhaseOutcome {
  const StartupPhasePending();

  @override
  String get code => 'pending';
  @override
  bool get isTerminal => false;
  @override
  bool get retryable => false;
}

final class StartupPhaseRunning extends StartupPhaseOutcome {
  const StartupPhaseRunning();

  @override
  String get code => 'running';
  @override
  bool get isTerminal => false;
  @override
  bool get retryable => false;
}

final class StartupPhaseSucceeded extends StartupPhaseOutcome {
  const StartupPhaseSucceeded();

  @override
  String get code => 'succeeded';
  @override
  bool get isTerminal => true;
  @override
  bool get retryable => false;
}

final class StartupPhaseTimedOut extends StartupPhaseOutcome {
  const StartupPhaseTimedOut();

  @override
  String get code => 'timed_out';
  @override
  bool get isTerminal => true;
  @override
  bool get retryable => true;
}

final class StartupPhaseDegraded extends StartupPhaseOutcome {
  StartupPhaseDegraded(this.reasonCode) {
    _checkSafeIdentifier(reasonCode, 'reasonCode');
  }

  final String reasonCode;

  @override
  String get code => reasonCode;
  @override
  bool get isTerminal => true;
  @override
  bool get retryable => true;
}

final class StartupPhaseFailed extends StartupPhaseOutcome {
  StartupPhaseFailed({required this.reasonCode, required this.retryable}) {
    _checkSafeIdentifier(reasonCode, 'reasonCode');
  }

  final String reasonCode;

  @override
  String get code => reasonCode;
  @override
  bool get isTerminal => true;
  @override
  final bool retryable;
}

final class StartupPhaseCancelled extends StartupPhaseOutcome {
  const StartupPhaseCancelled();

  @override
  String get code => 'cancelled';
  @override
  bool get isTerminal => true;
  @override
  bool get retryable => true;
}

final class StartupPhaseSnapshot {
  const StartupPhaseSnapshot({
    required this.name,
    required this.dependency,
    required this.critical,
    required this.attempt,
    required this.outcome,
    this.startedAtUtc,
    this.finishedAtUtc,
    this.elapsed = Duration.zero,
    this.errorType,
  });

  final String name;
  final String dependency;
  final bool critical;
  final int attempt;
  final StartupPhaseOutcome outcome;
  final DateTime? startedAtUtc;
  final DateTime? finishedAtUtc;
  final Duration elapsed;
  final String? errorType;

  StartupPhaseSnapshot copyWith({
    int? attempt,
    StartupPhaseOutcome? outcome,
    DateTime? startedAtUtc,
    DateTime? finishedAtUtc,
    Duration? elapsed,
    String? errorType,
    bool clearFinishedAt = false,
    bool clearErrorType = false,
  }) => StartupPhaseSnapshot(
    name: name,
    dependency: dependency,
    critical: critical,
    attempt: attempt ?? this.attempt,
    outcome: outcome ?? this.outcome,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    finishedAtUtc: clearFinishedAt
        ? null
        : (finishedAtUtc ?? this.finishedAtUtc),
    elapsed: elapsed ?? this.elapsed,
    errorType: clearErrorType ? null : (errorType ?? this.errorType),
  );
}

enum StartupOverallStatus { idle, running, ready, degraded, failed }

final class StartupSnapshot {
  const StartupSnapshot({required this.status, required this.phases});

  final StartupOverallStatus status;
  final List<StartupPhaseSnapshot> phases;

  bool get isInteractive => true;
  bool get isTerminal =>
      status == StartupOverallStatus.ready ||
      status == StartupOverallStatus.degraded ||
      status == StartupOverallStatus.failed;
  bool get canRetry => phases.any(
    (phase) => phase.outcome.isTerminal && phase.outcome.retryable,
  );
}

void _checkSafeIdentifier(String value, String field) {
  if (!RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      field,
      'must be a lowercase diagnostic identifier',
    );
  }
}
