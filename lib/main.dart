import 'package:flutter/material.dart';

import 'ui/analytics.dart';
import 'ui/app.dart';
import 'ui/game_controller.dart';
import 'ui/sound.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Analytics.init();
  await Sound.init();
  final controller = await GameController.load();
  Analytics.attach(controller);
  runApp(AiLabTycoonApp(controller: controller));
}
