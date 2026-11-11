// OWNER: ui-core agent. STUB — replace.
import 'package:flutter/material.dart';

import '../game_controller.dart';

class HardwareScreen extends StatelessWidget {
  final GameController controller;
  const HardwareScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Hardware'));
}
