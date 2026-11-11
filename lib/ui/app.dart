// OWNER: ui-core agent. App shell, theme hookup, HUD and bottom navigation.
import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'moments/event_presenter.dart';
import 'moments/rivals_screen.dart';
import 'screens/hardware_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/research_screen.dart';
import 'sound.dart';
import 'theme.dart';
import 'widgets/game_builder.dart';
import 'widgets/hud.dart';
import 'widgets/panel.dart';

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
      home: HomeScreen(controller: controller),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final GameController controller;
  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      OverviewScreen(controller: c),
      HardwareScreen(controller: c),
      ResearchScreen(controller: c),
      RivalsScreen(controller: c),
    ];
    return EventPresenter(
      controller: c,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Hud(controller: c),
              Expanded(
                child: ContentFrame(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      // Hidden tabs skip per-tick rebuilds.
                      for (var i = 0; i < pages.length; i++)
                        TabActive(active: i == _tab, child: pages[i]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: ContentFrame(
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) {
                  if (i != _tab) Sound.play(Sfx.click);
                  setState(() => _tab = i);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_work_outlined),
                    selectedIcon: Icon(Icons.home_work),
                    label: 'Lab',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.memory_outlined),
                    selectedIcon: Icon(Icons.memory),
                    label: 'Hardware',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.science_outlined),
                    selectedIcon: Icon(Icons.science),
                    label: 'Research',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.leaderboard_outlined),
                    selectedIcon: Icon(Icons.leaderboard),
                    label: 'Rivals',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
