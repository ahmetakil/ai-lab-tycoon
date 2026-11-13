import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/ui/shell/game_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show withApp;

void main() {
  test('every new state gets a grid revision no earlier state used', () {
    final a = GameState()..touchGrid();
    final b = GameState();
    expect(b.gridRevision, isNot(a.gridRevision));
    expect(b.gridRevision, greaterThan(a.gridRevision));
  });

  testWidgets('reset is a full restart: fresh grid, money, screens and intro', (tester) async {
    await withApp(tester, (c) async {
      final g = c.game;
      g.s.money = 1e6;
      expect(c.act((g) => g.placeTile('garage', 0, 0, 'gpu_gamer')), isTrue);
      final shellBefore = tester.state(find.byType(GameShell));
      await c.resetGame();
      await tester.pump(const Duration(milliseconds: 300));
      final fresh = GameState();
      expect(c.game.s.grids, fresh.grids);
      expect(c.game.s.money, closeTo(fresh.money, 1));
      expect(c.game.s.gridRevision, isNot(g.s.gridRevision));
      // The whole shell is rebuilt (no stale build mode, caches or camera).
      expect(tester.state(find.byType(GameShell)), isNot(same(shellBefore)));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('intro_seen_v1'), isNull);
      expect(prefs.getBool('tutorial_done_v1'), isNull);
    });
  });
}
