// OWNER: ui-moments agent. STUB — replace.
// Wraps the app: listens to controller.events and shows toasts/overlays/sounds,
// the offline "while you were away" dialog, etc.
import 'package:flutter/material.dart';

import '../game_controller.dart';

class EventPresenter extends StatelessWidget {
  final GameController controller;
  final Widget child;
  const EventPresenter({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
