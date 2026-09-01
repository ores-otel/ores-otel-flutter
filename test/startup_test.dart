import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ores_otel_flutter/startup.dart';

void main() {
  test('hung dependency times out, cancels, and records a slow warning',
      () async {
    final clock = _ManualStartupClock();
    final diagnostics = StartupDiagnostics.create(
      appName: 'startup_test',
      clock: clock,
      emitToDeveloperLog: false,
    );
    StartupCancellationToken? observedCancellation;
    final coordinator = StartupCoordinator(
      diagnostics: diagnostics,
      tasks: [
        StartupTask(
          name: 'session_restore',
          dependency: 'shared_auth',
          slowWarningAfter: const Duration(seconds: 2),
          timeout: const Duration(seconds: 5),
          run: (cancellation) {
            observedCancellation = cancellation;
            return Completer<StartupTaskResult>().future;
          },
        ),
      ],
    );
    addTearDown(coordinator.dispose);

    coordinator.start();
    await _flushMicrotasks();
    expect(coordinator.value.status, StartupOverallStatus.running);

    clock.elapse(const Duration(seconds: 2));
    expect(
      diagnostics.buffer.entries.map((entry) => entry.event),
      contains(StartupEvent.startupPhaseSlow),
    );

    clock.elapse(const Duration(seconds: 3));
    await _flushMicrotasks();
    expect(observedCancellation?.isCancelled, isTrue);
    expect(coordinator.value.status, StartupOverallStatus.degraded);
    expect(
      coordinator.value.phases.single.outcome,
      isA<StartupPhaseTimedOut>(),
    );
  });

  test('throwing dependency is redacted and can succeed on retry', () async {
    final clock = _ManualStartupClock();
    final diagnostics = StartupDiagnostics.create(
      appName: 'startup_test',
      clock: clock,
      emitToDeveloperLog: false,
    );
    var attempts = 0;
    final coordinator = StartupCoordinator(
      diagnostics: diagnostics,
      tasks: [
        StartupTask(
          name: 'database_open',
          dependency: 'local_database',
          slowWarningAfter: const Duration(seconds: 1),
          timeout: const Duration(seconds: 3),
          run: (_) async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('password=must-not-enter-diagnostics');
            }
            return const StartupTaskSucceeded();
          },
        ),
      ],
    );
    addTearDown(coordinator.dispose);

    coordinator.start();
    await _flushMicrotasks();
    expect(coordinator.value.status, StartupOverallStatus.degraded);
    expect(diagnostics.buffer.exportJsonLines(), isNot(contains('must-not')));
    expect(diagnostics.buffer.exportJsonLines(), contains('StateError'));

    await coordinator.retry('database_open');
    expect(attempts, 2);
    expect(coordinator.value.status, StartupOverallStatus.ready);
  });

  test('offline dependency enters a typed, usable degraded state', () async {
    final diagnostics = StartupDiagnostics.create(
      appName: 'startup_test',
      clock: _ManualStartupClock(),
      emitToDeveloperLog: false,
    );
    final coordinator = StartupCoordinator(
      diagnostics: diagnostics,
      tasks: [
        StartupTask(
          name: 'connectivity_probe',
          dependency: 'network',
          slowWarningAfter: const Duration(seconds: 1),
          timeout: const Duration(seconds: 3),
          run: (_) async => StartupTaskDegraded(reasonCode: 'offline'),
        ),
      ],
    );
    addTearDown(coordinator.dispose);

    coordinator.start();
    await _flushMicrotasks();
    expect(coordinator.value.status, StartupOverallStatus.degraded);
    expect(coordinator.value.isInteractive, isTrue);
    expect(
      coordinator.value.phases.single.outcome,
      isA<StartupPhaseDegraded>(),
    );
  });

  test('diagnostic export is versioned and remains ring-buffer bounded', () {
    final buffer = StartupDiagnosticBuffer(capacity: 16);
    final diagnostics = StartupDiagnostics.create(
      appName: 'startup_test',
      clock: _ManualStartupClock(),
      buffer: buffer,
      emitToDeveloperLog: false,
    );

    for (var index = 0; index < 20; index += 1) {
      diagnostics.record(StartupEvent.startupStarted, retryCount: index);
    }

    expect(buffer.entries, hasLength(16));
    expect(buffer.entries.first.retryCount, 4);
    expect(buffer.exportJsonLines(), contains('"redaction_version":1'));
    expect(buffer.exportJsonLines(), contains('"launch_id"'));
  });

  testWidgets(
    'first frame and actions remain interactive while a dependency hangs',
    (tester) async {
      final clock = _ManualStartupClock();
      final diagnostics = StartupDiagnostics.create(
        appName: 'startup_widget_test',
        clock: clock,
        emitToDeveloperLog: false,
      );
      var attempts = 0;

      await tester.pumpWidget(
        OresStartupGate(
          diagnostics: diagnostics,
          tasks: [
            StartupTask(
              name: 'remote_warmup',
              dependency: 'remote_api',
              slowWarningAfter: const Duration(seconds: 1),
              timeout: const Duration(seconds: 3),
              run: (_) {
                attempts += 1;
                if (attempts == 1) {
                  return Completer<StartupTaskResult>().future;
                }
                return Future.value(const StartupTaskSucceeded());
              },
            ),
          ],
          builder: (context, startup, coordinator) => MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  const Text('Interactive app content'),
                  FilledButton(
                    key: const ValueKey('primary-action'),
                    onPressed: () {},
                    child: const Text('Primary action'),
                  ),
                  OresStartupStatusPanel(
                    snapshot: startup,
                    coordinator: coordinator,
                    diagnostics: diagnostics,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Interactive app content'), findsOneWidget);
      expect(find.byKey(const ValueKey('primary-action')), findsOneWidget);
      expect(
        diagnostics.buffer.entries.map((entry) => entry.event),
        contains(StartupEvent.firstFrameRendered),
      );

      clock.elapse(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Available with limited services'), findsOneWidget);
      await tester.tap(find.text('Retry startup'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('primary-action')), findsOneWidget);
    },
  );
}

Future<void> _flushMicrotasks() async {
  await Future<void>.value();
  await Future<void>.value();
}

final class _ManualStartupClock implements StartupClock {
  DateTime _now = DateTime.utc(2026, 8, 31, 12);
  final List<_ManualScheduledCallback> _scheduled = [];

  @override
  DateTime nowUtc() => _now;

  @override
  StartupScheduledCallback schedule(
    Duration delay,
    void Function() callback,
  ) {
    final scheduled = _ManualScheduledCallback(
      deadline: _now.add(delay),
      callback: callback,
    );
    _scheduled.add(scheduled);
    return scheduled;
  }

  void elapse(Duration duration) {
    final target = _now.add(duration);
    while (true) {
      final due = _scheduled
          .where(
              (entry) => !entry.isCancelled && !entry.deadline.isAfter(target))
          .toList()
        ..sort((left, right) => left.deadline.compareTo(right.deadline));
      if (due.isEmpty) break;
      final next = due.first;
      _now = next.deadline;
      next.cancel();
      next.callback();
    }
    _now = target;
  }
}

final class _ManualScheduledCallback implements StartupScheduledCallback {
  _ManualScheduledCallback({required this.deadline, required this.callback});

  final DateTime deadline;
  final void Function() callback;
  bool isCancelled = false;

  @override
  void cancel() => isCancelled = true;
}
