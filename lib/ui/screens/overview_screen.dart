// OWNER: ui-core agent. STUB — replace.
import 'package:flutter/material.dart';

import '../game_controller.dart';

class OverviewScreen extends StatelessWidget {
  final GameController controller;
  const OverviewScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Overview'));
}
