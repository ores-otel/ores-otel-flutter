import 'package:ores_otel_flutter/startup.dart';
import 'package:ores_otel_flutter/src/app.dart';

void main() => runOresFlutterApp(
      appName: 'ores_otel_flutter',
      builder: (diagnostics) => OresStartupGate(
        diagnostics: diagnostics,
        tasks: const [],
        builder: (context, startup, coordinator) => const OresOtelApp(),
      ),
    );
