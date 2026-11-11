// OWNER: ui-core agent. App shell, theme hookup and bottom navigation.
import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'moments/event_presenter.dart';
import 'moments/rivals_screen.dart';
import 'screens/hardware_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/research_screen.dart';
import 'theme.dart';

class AiLabTycoonApp extends StatelessWidget {
  final GameController controller;
  const AiLabTycoonApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Lab Tycoon',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
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
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_work_outlined), label: 'Lab'),
            NavigationDestination(icon: Icon(Icons.memory), label: 'Hardware'),
            NavigationDestination(icon: Icon(Icons.science_outlined), label: 'Research'),
            NavigationDestination(icon: Icon(Icons.leaderboard_outlined), label: 'Rivals'),
          ],
        ),
      ),
    );
  }
}
