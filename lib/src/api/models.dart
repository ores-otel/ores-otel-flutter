class ConnectionStatus {
  const ConnectionStatus({required this.connected, required this.endpoint});
  final bool connected;
  final String endpoint;

  @override
  bool operator ==(Object other) =>
      other is ConnectionStatus &&
      connected == other.connected &&
      endpoint == other.endpoint;

  @override
  int get hashCode => Object.hash(connected, endpoint);
}

enum OtelLogLevel { debug, info, warn, error }
