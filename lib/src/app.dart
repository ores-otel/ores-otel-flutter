import 'package:flutter/material.dart';

import 'connection_log.dart';
import 'home_page.dart';
import 'theme.dart';

class OresOtelApp extends StatefulWidget {
  const OresOtelApp({super.key, this.connectionLog});

  /// Injected in tests. Production owns and disposes the bus.
  final ConnectionLogBus? connectionLog;

  @override
  State<OresOtelApp> createState() => _OresOtelAppState();
}

class _OresOtelAppState extends State<OresOtelApp> {
  late final ConnectionLogBus _connectionLog;
  late final bool _ownsConnectionLog;

  @override
  void initState() {
    super.initState();
    _ownsConnectionLog = widget.connectionLog == null;
    _connectionLog = widget.connectionLog ?? ConnectionLogBus();
  }

  @override
  void dispose() {
    if (_ownsConnectionLog) _connectionLog.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ores-otel',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: HomePage(connectionLog: _connectionLog),
    );
  }
}
