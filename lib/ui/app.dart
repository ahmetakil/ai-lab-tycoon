// App shell: theme hookup and the game screen.
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
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: GameShell(controller: controller),
    );
  }
}
