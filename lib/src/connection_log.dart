import 'package:rxdart/rxdart.dart';

import 'api/models.dart';

/// Connection + log-level snapshot owned at the telemetry effect boundary.
///
/// Replaces a hardcoded [ConnectionStatus] constructed inside widgets and the
/// always-disconnected [ApiClient.snapshot] stand-in. Duplicate values are
/// collapsed with [distinct] so listeners do not rebuild on no-ops.
class ConnectionLogSnapshot {
  const ConnectionLogSnapshot({
    required this.connected,
    required this.endpoint,
    required this.logLevel,
  });

  final bool connected;
  final String endpoint;
  final OtelLogLevel logLevel;

  ConnectionStatus get status =>
      ConnectionStatus(connected: connected, endpoint: endpoint);

  @override
  bool operator ==(Object other) =>
      other is ConnectionLogSnapshot &&
      connected == other.connected &&
      endpoint == other.endpoint &&
      logLevel == other.logLevel;

  @override
  int get hashCode => Object.hash(connected, endpoint, logLevel);
}

class ConnectionLogBus {
  ConnectionLogBus({
    this.seed = const ConnectionLogSnapshot(
      connected: false,
      endpoint: 'unset',
      logLevel: OtelLogLevel.info,
    ),
  }) : _subject = BehaviorSubject.seeded(seed);

  final ConnectionLogSnapshot seed;
  final BehaviorSubject<ConnectionLogSnapshot> _subject;

  Stream<ConnectionLogSnapshot> get snapshots => _subject.stream.distinct();

  ConnectionLogSnapshot get value => _subject.value;

  void publish(ConnectionLogSnapshot next) => _subject.add(next);

  void close() => _subject.close();
}
