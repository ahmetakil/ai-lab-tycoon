import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/game_controller.dart';
import 'ui/sound.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Sound.init();
  final controller = await GameController.load();
  runApp(AiLabTycoonApp(controller: controller));
}
