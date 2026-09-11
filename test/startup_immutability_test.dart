import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/startup.dart';

void main() {
  test('detached startup snapshots rebuild and seal nested values', () {
    final phase = StartupPhaseSnapshot(
      name: 'telemetry_boot',
      dependency: 'collector',
      critical: true,
      attempt: 2,
      outcome: StartupPhaseDegraded('offline'),
      startedAtUtc: DateTime.utc(2026, 9, 11, 12),
      finishedAtUtc: DateTime.utc(2026, 9, 11, 12, 0, 1),
      elapsed: const Duration(seconds: 1),
      errorType: 'SocketException',
    );
    final source = <StartupPhaseSnapshot>[phase];

    final snapshot = StartupSnapshot.detached(
      status: StartupOverallStatus.degraded,
      phases: source,
    );

    source.clear();
    expect(snapshot.phases, hasLength(1));
    final detached = snapshot.phases.single;
    expect(identical(detached, phase), isFalse);
    expect(identical(detached.outcome, phase.outcome), isFalse);
    expect(identical(detached.startedAtUtc, phase.startedAtUtc), isFalse);
    expect(identical(detached.finishedAtUtc, phase.finishedAtUtc), isFalse);
    expect(detached.name, phase.name);
    expect(detached.dependency, phase.dependency);
    expect(detached.critical, phase.critical);
    expect(detached.attempt, phase.attempt);
    expect(detached.outcome.code, phase.outcome.code);
    expect(detached.elapsed, phase.elapsed);
    expect(detached.errorType, phase.errorType);
    expect(
      () => snapshot.phases.add(phase),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('phase detachedCopy preserves values without sharing outcome identity', () {
    final phase = StartupPhaseSnapshot(
      name: 'database_open',
      dependency: 'local_database',
      critical: false,
      attempt: 3,
      outcome: StartupPhaseFailed(reasonCode: 'io_error', retryable: true),
      elapsed: const Duration(milliseconds: 12),
    );

    final copy = phase.detachedCopy();

    expect(identical(copy, phase), isFalse);
    expect(identical(copy.outcome, phase.outcome), isFalse);
    expect(copy.name, phase.name);
    expect(copy.dependency, phase.dependency);
    expect(copy.attempt, phase.attempt);
    expect(copy.outcome.code, 'io_error');
    expect(copy.outcome.retryable, isTrue);
    expect(copy.elapsed, phase.elapsed);
  });
}
