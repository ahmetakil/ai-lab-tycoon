import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/run_phases.dart';

/// For `g.advance(..., onStep: decideDefaults(g))`: online, a checkpoint
/// waits for the player forever, so tests that run through a whole training
/// run answer each one with its default.
void Function() decideDefaults(Game g) => () {
  final p = g.awaitingPhase;
  if (p != null) g.choosePhase(defaultPhaseOption(p, g.s.run!.spec));
};
