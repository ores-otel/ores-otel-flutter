import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'clock.dart';

enum StartupLogLevel { debug, info, warning, error }

enum StartupEvent {
  appLaunch,
  firstFrameRendered,
  lifecycleChanged,
  startupStarted,
  startupPhaseStarted,
  startupPhaseSlow,
  startupPhaseCompleted,
  startupCompleted,
  uncaughtFlutterError,
  uncaughtPlatformError,
  uncaughtZoneError,
}

extension on StartupEvent {
  String get wireName => switch (this) {
        StartupEvent.appLaunch => 'app_launch',
        StartupEvent.firstFrameRendered => 'first_frame_rendered',
        StartupEvent.lifecycleChanged => 'lifecycle_changed',
        StartupEvent.startupStarted => 'startup_started',
        StartupEvent.startupPhaseStarted => 'startup_phase_started',
        StartupEvent.startupPhaseSlow => 'startup_phase_slow',
        StartupEvent.startupPhaseCompleted => 'startup_phase_completed',
        StartupEvent.startupCompleted => 'startup_completed',
        StartupEvent.uncaughtFlutterError => 'uncaught_flutter_error',
        StartupEvent.uncaughtPlatformError => 'uncaught_platform_error',
        StartupEvent.uncaughtZoneError => 'uncaught_zone_error',
      };
}

final class StartupDiagnosticEvent {
  const StartupDiagnosticEvent({
    required this.timestampUtc,
    required this.appName,
    required this.launchId,
    required this.event,
    required this.level,
    this.phase,
    this.dependency,
    this.outcome,
    this.elapsed,
    this.retryCount,
    this.errorType,
    this.lifecycleState,
    this.stackTrace,
  });

  final DateTime timestampUtc;
  final String appName;
  final String launchId;
  final StartupEvent event;
  final StartupLogLevel level;
  final String? phase;
  final String? dependency;
  final String? outcome;
  final Duration? elapsed;
  final int? retryCount;
  final String? errorType;
  final String? lifecycleState;
  final String? stackTrace;

  Map<String, Object> toJson() => {
        'timestamp': timestampUtc.toIso8601String(),
        'app_name': appName,
        'launch_id': launchId,
        'event': event.wireName,
        'level': level.name,
        'redaction_version': 1,
        if (phase != null) 'phase': phase!,
        if (dependency != null) 'dependency': dependency!,
        if (outcome != null) 'outcome': outcome!,
        if (elapsed != null) 'elapsed_ms': elapsed!.inMilliseconds,
        if (retryCount != null) 'retry_count': retryCount!,
        if (errorType != null) 'error_type': errorType!,
        if (lifecycleState != null) 'lifecycle_state': lifecycleState!,
        if (stackTrace != null) 'stack_trace': stackTrace!,
      };
}

abstract interface class StartupDiagnosticSink {
  void write(StartupDiagnosticEvent event);
}

/// Bounded, memory-only launch diagnostics retrievable by users and tests.
final class StartupDiagnosticBuffer implements StartupDiagnosticSink {
  StartupDiagnosticBuffer({this.capacity = 256}) {
    if (capacity < 16 || capacity > 4096) {
      throw ArgumentError.value(capacity, 'capacity', 'must be 16..4096');
    }
  }

  final int capacity;
  final List<StartupDiagnosticEvent> _entries = [];

  List<StartupDiagnosticEvent> get entries => List.unmodifiable(_entries);

  String exportJsonLines() => _entries.map((event) {
        return jsonEncode(event.toJson());
      }).join('\n');

  @override
  void write(StartupDiagnosticEvent event) {
    if (_entries.length == capacity) _entries.removeAt(0);
    _entries.add(event);
  }
}

final class DeveloperStartupDiagnosticSink implements StartupDiagnosticSink {
  const DeveloperStartupDiagnosticSink();

  @override
  void write(StartupDiagnosticEvent event) {
    final encoded = jsonEncode(event.toJson());
    developer.log(
      encoded,
      name: 'ores.startup',
      level: switch (event.level) {
        StartupLogLevel.debug => 500,
        StartupLogLevel.info => 800,
        StartupLogLevel.warning => 900,
        StartupLogLevel.error => 1000,
      },
    );
    debugPrint('ores.startup $encoded');
  }
}

final class StartupDiagnostics {
  StartupDiagnostics({
    required this.clock,
    required this.appName,
    required this.launchId,
    required this.launchStartedAtUtc,
    StartupDiagnosticBuffer? buffer,
    List<StartupDiagnosticSink> sinks = const [],
    bool emitToDeveloperLog = true,
  })  : buffer = buffer ?? StartupDiagnosticBuffer(),
        _sinks = [
          if (emitToDeveloperLog) const DeveloperStartupDiagnosticSink(),
          ...sinks,
        ] {
    _checkDiagnosticIdentifier(appName, 'appName');
    if (!RegExp(r'^[a-z0-9]{6,32}-[a-z0-9]{1,8}$').hasMatch(launchId)) {
      throw ArgumentError.value(launchId, 'launchId', 'invalid launch id');
    }
  }

  factory StartupDiagnostics.create({
    required String appName,
    StartupClock clock = const SystemStartupClock(),
    StartupDiagnosticBuffer? buffer,
    List<StartupDiagnosticSink> sinks = const [],
    bool emitToDeveloperLog = true,
  }) {
    final startedAt = clock.nowUtc();
    final timestamp = startedAt.microsecondsSinceEpoch.toRadixString(36);
    final sequence = _nextLaunchSequence++;
    return StartupDiagnostics(
      clock: clock,
      appName: appName,
      launchId: '$timestamp-${sequence.toRadixString(36)}',
      launchStartedAtUtc: startedAt,
      buffer: buffer,
      sinks: sinks,
      emitToDeveloperLog: emitToDeveloperLog,
    );
  }

  static int _nextLaunchSequence = 0;

  final StartupClock clock;
  final String appName;
  final String launchId;
  final DateTime launchStartedAtUtc;
  final StartupDiagnosticBuffer buffer;
  final List<StartupDiagnosticSink> _sinks;

  void record(
    StartupEvent event, {
    StartupLogLevel level = StartupLogLevel.info,
    String? phase,
    String? dependency,
    String? outcome,
    Duration? elapsed,
    int? retryCount,
    Object? error,
    StackTrace? stackTrace,
    String? lifecycleState,
  }) {
    if (phase != null) _checkDiagnosticIdentifier(phase, 'phase');
    if (dependency != null) {
      _checkDiagnosticIdentifier(dependency, 'dependency');
    }
    if (outcome != null) _checkDiagnosticIdentifier(outcome, 'outcome');
    final diagnostic = StartupDiagnosticEvent(
      timestampUtc: clock.nowUtc(),
      appName: appName,
      launchId: launchId,
      event: event,
      level: level,
      phase: phase,
      dependency: dependency,
      outcome: outcome,
      elapsed: _boundedElapsed(elapsed),
      retryCount: retryCount?.clamp(0, 100),
      errorType: error == null ? null : _safeErrorType(error),
      lifecycleState: lifecycleState,
      stackTrace: stackTrace == null ? null : _redactStackTrace(stackTrace),
    );
    buffer.write(diagnostic);
    for (final sink in _sinks) {
      sink.write(diagnostic);
    }
  }
}

Duration? _boundedElapsed(Duration? elapsed) {
  if (elapsed == null) return null;
  if (elapsed.isNegative) return Duration.zero;
  const maximum = Duration(hours: 1);
  return elapsed > maximum ? maximum : elapsed;
}

void _checkDiagnosticIdentifier(String value, String field) {
  if (!RegExp(r'^[a-z][a-z0-9_.-]{0,63}$').hasMatch(value)) {
    throw ArgumentError.value(value, field, 'invalid diagnostic identifier');
  }
}

String _safeErrorType(Object error) {
  final normalized =
      error.runtimeType.toString().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final prefixed = RegExp(r'^[A-Za-z]').hasMatch(normalized)
      ? normalized
      : 'Error_$normalized';
  return prefixed.length > 128 ? prefixed.substring(0, 128) : prefixed;
}

String _redactStackTrace(StackTrace stackTrace) {
  final firstFrames = stackTrace.toString().split('\n').take(12).join('\n');
  return firstFrames
      .replaceAll(RegExp(r'/Users/[^/]+/'), '/Users/<redacted>/')
      .replaceAll(RegExp(r'\\Users\\[^\\]+\\'), r'\Users\<redacted>\')
      .replaceAll(RegExp(r'([?&][^=\s]+)=([^&\s]+)'), r'$1=<redacted>')
      .replaceAll(
        RegExp(
          r'(bearer|token|secret|password)\s+[^\s]+',
          caseSensitive: false,
        ),
        r'$1 <redacted>',
      );
}
