import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'coordinator.dart';
import 'diagnostics.dart';
import 'model.dart';

typedef StartupWidgetBuilder = Widget Function(
  BuildContext context,
  StartupSnapshot startup,
  StartupCoordinator coordinator,
);

/// Renders [builder] immediately and starts dependencies only after its first
/// frame has been presented.
final class OresStartupGate extends StatefulWidget {
  const OresStartupGate({
    super.key,
    required this.diagnostics,
    required this.tasks,
    required this.builder,
    this.coordinator,
  });

  final StartupDiagnostics diagnostics;
  final List<StartupTask> tasks;
  final StartupWidgetBuilder builder;
  final StartupCoordinator? coordinator;

  @override
  State<OresStartupGate> createState() => _OresStartupGateState();
}

final class _OresStartupGateState extends State<OresStartupGate>
    with WidgetsBindingObserver {
  late final StartupCoordinator _coordinator;
  late final bool _ownsCoordinator;

  @override
  void initState() {
    super.initState();
    _ownsCoordinator = widget.coordinator == null;
    _coordinator = widget.coordinator ??
        StartupCoordinator(
          tasks: widget.tasks,
          diagnostics: widget.diagnostics,
        );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.diagnostics.record(
        StartupEvent.firstFrameRendered,
        elapsed: widget.diagnostics.clock.nowUtc().difference(
              widget.diagnostics.launchStartedAtUtc,
            ),
      );
      _coordinator.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.diagnostics.record(
      StartupEvent.lifecycleChanged,
      lifecycleState: state.name,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsCoordinator) _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StartupDiagnosticsScope(
      diagnostics: widget.diagnostics,
      child: AnimatedBuilder(
        animation: _coordinator,
        builder: (context, _) =>
            widget.builder(context, _coordinator.value, _coordinator),
      ),
    );
  }
}

final class StartupDiagnosticsScope extends InheritedWidget {
  const StartupDiagnosticsScope({
    super.key,
    required this.diagnostics,
    required super.child,
  });

  final StartupDiagnostics diagnostics;

  static StartupDiagnostics of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<StartupDiagnosticsScope>();
    assert(scope != null, 'No StartupDiagnosticsScope found');
    return scope!.diagnostics;
  }

  @override
  bool updateShouldNotify(StartupDiagnosticsScope oldWidget) =>
      diagnostics != oldWidget.diagnostics;
}

/// Compact, responsive status surface suitable for an app shell or splash.
final class OresStartupStatusPanel extends StatelessWidget {
  const OresStartupStatusPanel({
    super.key,
    required this.snapshot,
    required this.coordinator,
    required this.diagnostics,
  });

  final StartupSnapshot snapshot;
  final StartupCoordinator coordinator;
  final StartupDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (snapshot.status == StartupOverallStatus.running)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _statusLabel(snapshot.status),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final phase in snapshot.phases)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(phase.dependency)),
                    Text(phase.outcome.code),
                    if (phase.outcome.isTerminal && phase.outcome.retryable)
                      IconButton(
                        tooltip: 'Retry ${phase.dependency}',
                        onPressed: () =>
                            unawaited(coordinator.retry(phase.name)),
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (snapshot.canRetry)
                  FilledButton.icon(
                    onPressed: () => unawaited(coordinator.retryAll()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry startup'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      showStartupDiagnosticsDialog(context, diagnostics),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Diagnostics'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showStartupDiagnosticsDialog(
  BuildContext context,
  StartupDiagnostics diagnostics,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Launch ${diagnostics.launchId}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480),
        child: SingleChildScrollView(
          child: SelectableText(
            diagnostics.buffer.exportJsonLines(),
            key: const ValueKey('startup-diagnostics'),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: diagnostics.buffer.exportJsonLines()),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

String _statusLabel(StartupOverallStatus status) => switch (status) {
      StartupOverallStatus.idle => 'Opening…',
      StartupOverallStatus.running => 'Finishing setup…',
      StartupOverallStatus.ready => 'Ready',
      StartupOverallStatus.degraded => 'Available with limited services',
      StartupOverallStatus.failed => 'Setup needs attention',
    };
