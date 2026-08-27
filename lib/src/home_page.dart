import 'package:flutter/material.dart';

import 'connection_log.dart';
import 'widgets/status_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.connectionLog});

  final ConnectionLogBus connectionLog;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionLogSnapshot>(
      stream: connectionLog.snapshots,
      initialData: connectionLog.value,
      builder: (context, snapshot) {
        final status = (snapshot.data ?? connectionLog.value).status;
        return Scaffold(
          appBar: AppBar(title: const Text('ores-otel')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: StatusCard(status: status),
          ),
        );
      },
    );
  }
}
