// OWNER: ui-moments agent. STUB — replace.
// Called by the overview screen when a trained model is pending release.
import 'package:flutter/material.dart';

import '../game_controller.dart';

Future<void> showReleaseSheet(BuildContext context, GameController controller) async {
  controller.act((g) => g.release(open: false));
}
