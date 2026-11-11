// OWNER: ui-moments agent. First-launch intro: 3 quick cards + name your lab.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import 'moments_style.dart';

Future<void> showIntro(BuildContext context, GameController controller) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) => IntroFlow(controller: controller),
    transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  );
}

class IntroFlow extends StatefulWidget {
  final GameController controller;
  const IntroFlow({super.key, required this.controller});

  @override
  State<IntroFlow> createState() => _IntroFlowState();
}

class _IntroFlowState extends State<IntroFlow> {
  final _pages = PageController();
  late final _name = TextEditingController(text: widget.controller.game.s.labName);
  int _page = 0;

  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    Sound.play(Sfx.click);
    if (_page < _count - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _finish() {
    final name = _name.text.trim();
    if (name.isNotEmpty) widget.controller.act((g) => g.s.labName = name);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const EraBackdrop(Era.garage),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0xE6000000)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: (i) => setState(() => _page = i),
                        children: [
                          _IntroCard(
                            art: const GameImageOr(path: GameArt.playerLab, icon: Icons.memory_rounded),
                            kicker: 'AI LAB TYCOON',
                            title: 'One GPU.\nOne garage.\nOne dream.',
                            body:
                                'Grow an AI lab from a gaming GPU to a frontier datacenter, '
                                'and race the big labs through history.',
                          ),
                          const _IntroCard(
                            art: _LoopDiagram(),
                            kicker: 'THE LOOP',
                            title: 'Serve. Train. Ship.',
                            body:
                                'Serving users makes money now. Training makes a better model later. '
                                'Release models to win users and pass rival labs like ClosedAI and '
                                'Anthropomorphic. Spend on GPUs or on smarter software.',
                          ),
                          _IntroCard(
                            art: const GameImageOr(path: GameArt.logo, icon: Icons.badge_rounded),
                            kicker: 'LAST THING',
                            title: 'Name your lab',
                            body: 'It goes on every model card you share. Choose wisely. Or don\'t.',
                            extra: Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: TextField(
                                controller: _name,
                                maxLength: 28,
                                textAlign: TextAlign.center,
                                textCapitalization: TextCapitalization.words,
                                style: display(context, 22),
                                onSubmitted: (_) => _finish(),
                                decoration: InputDecoration(
                                  counterText: '',
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.06),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  hintText: 'Garage Labs',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _count; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.all(4),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? scheme.primary : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: display(context, 18),
                          ),
                          child: Text(_page == _count - 1 ? 'Open the garage' : 'Next'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GameImageOr extends StatelessWidget {
  final String path;
  final IconData icon;
  const GameImageOr({super.key, required this.path, required this.icon});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Image.asset(
      path,
      width: 150,
      height: 150,
      errorBuilder:
          (_, __, ___) => Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
              color: accent.withValues(alpha: 0.08),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 40)],
            ),
            child: Icon(icon, size: 56, color: accent),
          ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final Widget art;
  final String kicker, title, body;
  final Widget? extra;
  const _IntroCard({required this.art, required this.kicker, required this.title, required this.body, this.extra});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
      child: Column(
        children: [
          SizedBox(height: 160, child: Center(child: art)),
          const SizedBox(height: 28),
          Text(kicker, style: mono(context, 13, color: accent, weight: FontWeight.w700).copyWith(letterSpacing: 4)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: display(context, 38, color: Colors.white, height: 1.08, weight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: display(context, 16, color: Colors.white70, weight: FontWeight.w400, height: 1.4),
          ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

class _LoopDiagram extends StatelessWidget {
  const _LoopDiagram();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget node(IconData i, String label, Color c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: 0.12),
            border: Border.all(color: c, width: 2),
          ),
          child: Icon(i, color: c),
        ),
        const SizedBox(height: 6),
        Text(label, style: mono(context, 11, color: Colors.white70)),
      ],
    );
    Widget arrow() => const Padding(
      padding: EdgeInsets.only(bottom: 18),
      child: Icon(Icons.arrow_forward_rounded, color: Colors.white38),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        node(Icons.people_alt_rounded, 'serve', accent),
        arrow(),
        node(Icons.model_training_rounded, 'train', Neon.cyan),
        arrow(),
        node(Icons.rocket_launch_rounded, 'ship', Neon.magenta),
      ],
    );
  }
}
