import 'package:flutter/material.dart';

import '../theme.dart';

/// Gently breathes (glow + slight scale) while [active]. Used for alerts and
/// the "Release model" call to action.
class Pulse extends StatefulWidget {
  final Widget child;
  final bool active;
  final double scale;
  final Duration period;

  const Pulse({
    super.key,
    required this.child,
    this.active = true,
    this.scale = 1.03,
    this.period = const Duration(milliseconds: 1100),
  });

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: widget.scale,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// A value-driven opacity blink (for alarm dots/borders). Rebuilds only its
/// own small subtree.
class Blink extends StatefulWidget {
  final Widget Function(BuildContext context, double t) builder;
  final Duration period;
  const Blink({super.key, required this.builder, this.period = const Duration(milliseconds: 900)});

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => widget.builder(context, Curves.easeInOut.transform(_c.value)),
  );
}

/// Pops (quick scale bump) whenever [trigger] changes, e.g. the owned count
/// after a purchase.
class PopOnChange extends StatefulWidget {
  final Object? trigger;
  final Widget child;
  final double scale;
  const PopOnChange({super.key, required this.trigger, required this.child, this.scale = 1.25});

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(PopOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      // Up fast, settle back with a little overshoot.
      final t = _c.value;
      final bump =
          t < 0.35
              ? Curves.easeOut.transform(t / 0.35)
              : 1 - Curves.elasticOut.transform((t - 0.35) / 0.65);
      return Transform.scale(scale: 1 + (widget.scale - 1) * bump, child: child);
    },
    child: widget.child,
  );
}

/// Smoothly tweens a number and renders it with [format].
class AnimatedNumber extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final Duration duration;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text(format(v), style: style, maxLines: 1),
  );
}

/// Primary call-to-action with a press bounce. [color] defines the tone.
class NeonButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final bool dense;
  final bool expand;
  final String? sublabel;

  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.neon,
    this.filled = true,
    this.dense = false,
    this.expand = false,
    this.sublabel,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final c = enabled ? widget.color : AppColors.faint;
    final filled = widget.filled && enabled;
    final fg = filled ? AppColors.bg : c;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.dense ? 15 : 18, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.dense ? 13 : 15,
                  letterSpacing: 0.2,
                ),
              ),
              if (widget.sublabel != null)
                Text(
                  widget.sublabel!,
                  maxLines: 1,
                  style: numStyle(size: 11, color: fg.withValues(alpha: 0.8)),
                ),
            ],
          ),
        ),
      ],
    );
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense ? 12 : 18,
                vertical: widget.dense ? 8 : 13,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: filled ? c : c.withValues(alpha: enabled ? 0.10 : 0.06),
                border: Border.all(color: c.withValues(alpha: filled ? 1 : 0.5)),
                boxShadow: [
                  if (filled)
                    BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: -2),
                ],
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
