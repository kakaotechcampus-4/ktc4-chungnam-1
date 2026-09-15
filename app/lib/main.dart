import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'design/theme.dart';

void main() {
  runApp(const ProviderScope(child: SaerokApp()));
}

class SaerokApp extends StatefulWidget {
  const SaerokApp({super.key});

  @override
  State<SaerokApp> createState() => _SaerokAppState();
}

class _SaerokAppState extends State<SaerokApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '새록',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
