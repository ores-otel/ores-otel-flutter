import 'package:flutter/material.dart';

import 'home_page.dart';
import 'theme.dart';

class OresOtelApp extends StatelessWidget {
  const OresOtelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ores-otel',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const HomePage(),
    );
  }
}

