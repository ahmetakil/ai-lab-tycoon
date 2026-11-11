// Centered modal cards over the dimmed map (Game Dev Tycoon style). The world
// keeps ticking behind them.
import 'package:flutter/material.dart';

import '../sound.dart';
import '../theme.dart';

Future<T?> showGameModal<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  IconData? icon,
  Color color = AppColors.neon,
  double maxWidth = 560,

  /// Content scrolls itself (ListView); otherwise it's wrapped in a scroll view.
  bool selfScrolling = false,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0xA6000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (context, a, b) => GameModalCard(
          title: title,
          icon: icon,
          color: color,
          maxWidth: maxWidth,
          selfScrolling: selfScrolling,
          padding: padding,
          child: child,
        ),
    transitionBuilder:
        (context, a, b, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(
              begin: 0.92,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
            child: child,
          ),
        ),
  );
}

class GameModalCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color color;
  final double maxWidth;
  final bool selfScrolling;
  final EdgeInsets padding;
  final Widget child;

  const GameModalCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.color = AppColors.neon,
    this.maxWidth = 560,
    this.selfScrolling = false,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final body = selfScrolling ? child : SingleChildScrollView(padding: padding, child: child);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final maxH = box.maxHeight * 0.92;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxH),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xF20B1220),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 30),
                        const BoxShadow(
                          color: Color(0xCC000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  color.withValues(alpha: 0.22),
                                  color.withValues(alpha: 0.04),
                                ],
                              ),
                              border: Border(
                                bottom: BorderSide(color: color.withValues(alpha: 0.3)),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (icon != null) ...[
                                  Icon(icon, color: color, size: 20),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('modal-close'),
                                  tooltip: 'Close',
                                  icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                                  onPressed: () {
                                    Sound.play(Sfx.click);
                                    Navigator.of(context).maybePop();
                                  },
                                ),
                              ],
                            ),
                          ),
                          Flexible(child: body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
