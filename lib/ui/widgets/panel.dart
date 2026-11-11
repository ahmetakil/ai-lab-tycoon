import 'package:flutter/material.dart';

import '../theme.dart';

/// The standard card: dark surface, thin border, optional neon accent glow.
class Panel extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final bool glow;
  final EdgeInsetsGeometry padding;
  final double opacity;

  const Panel({
    super.key,
    required this.child,
    this.accent,
    this.glow = false,
    this.padding = const EdgeInsets.all(16),
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            a == null
                ? AppColors.surfaceHi
                : Color.alphaBlend(a.withValues(alpha: 0.07), AppColors.surfaceHi),
            AppColors.surface,
          ],
        ),
        border: Border.all(
          color: a == null ? AppColors.border : a.withValues(alpha: glow ? 0.75 : 0.35),
        ),
        boxShadow: [
          if (a != null && glow)
            BoxShadow(color: a.withValues(alpha: 0.22), blurRadius: 18, spreadRadius: -2),
        ],
      ),
      child: child,
    );
    return opacity < 1 ? Opacity(opacity: opacity, child: box) : box;
  }
}

/// Small caps header with an optional trailing widget.
class PanelHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color color;
  final Widget? trailing;

  const PanelHeader(
    this.title, {
    super.key,
    this.icon,
    this.color = AppColors.muted,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 6)],
          Expanded(child: Text(title.toUpperCase(), style: labelStyle(color: color))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A big section title between groups of cards.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  const SectionTitle(this.title, {super.key, this.subtitle, this.leading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded pill tag ("OPEN", "STARTUP", "+8% utilization").
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  final bool mono;

  const Tag(
    this.text, {
    super.key,
    this.color = AppColors.neon,
    this.icon,
    this.filled = false,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? AppColors.bg : color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  mono
                      ? numStyle(
                        size: 11.5,
                        color: filled ? AppColors.bg : color,
                        weight: FontWeight.w700,
                      )
                      : TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: filled ? AppColors.bg : color,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centres content and caps its width on wide screens.
class ContentFrame extends StatelessWidget {
  final Widget child;
  const ContentFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxContentWidth),
      child: child,
    ),
  );
}

/// Standard scrolling page body for a tab.
class TabScroll extends StatelessWidget {
  final List<Widget> children;
  const TabScroll({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: children);
  }
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
