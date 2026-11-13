// App shell: theme hookup and the game screen.
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'shell/game_shell.dart';
import 'theme.dart';

class AiLabTycoonApp extends StatelessWidget {
  final GameController controller;
  const AiLabTycoonApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Lab Tycoon',
      debugShowCheckedModeBanner: false,
      // Click-and-drag scrolls lists on web/desktop too, not just touch.
      scrollBehavior: const _DragEverywhere(),
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      // Keyed on the Game so a reset rebuilds every screen from scratch
      // (no build mode, camera, caches or animations from the old run).
      home: ValueListenableBuilder<int>(
        valueListenable: controller.resets,
        builder: (context, n, _) => GameShell(key: ValueKey('game-$n'), controller: controller),
      ),
    );
  }
}

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
