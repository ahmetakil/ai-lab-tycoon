import 'package:flutter/widgets.dart';

import '../game_controller.dart';

/// Marks whether a tab is the visible one. (Not TickerMode: a disabled
/// TickerMode also detaches Image error listeners, which makes missing art
/// throw instead of showing the fallback.)
class TabActive extends InheritedWidget {
  final bool active;
  const TabActive({super.key, required this.active, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabActive>()?.active ?? true;

  @override
  bool updateShouldNotify(TabActive old) => old.active != active;
}

/// Like ListenableBuilder on the controller, but skips rebuilds while its tab
/// is hidden (see [TabActive]). It catches up as soon as it becomes visible.
class GameBuilder extends StatefulWidget {
  final GameController controller;
  final WidgetBuilder builder;
  const GameBuilder({super.key, required this.controller, required this.builder});

  @override
  State<GameBuilder> createState() => _GameBuilderState();
}

class _GameBuilderState extends State<GameBuilder> {
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(GameBuilder old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TabActive.of(context);
  }

  void _onChange() {
    if (!mounted) return;
    // Hidden tabs skip; didChangeDependencies rebuilds them when shown.
    if (_active) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
