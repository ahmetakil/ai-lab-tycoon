// "What did that research actually do?" Snapshot the numbers a player cares
// about before and after a purchase, and explain the difference in plain words.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sim/balance.dart';
import '../sim/game.dart';
import 'format.dart';
import 'theme.dart';

class ImpactSnapshot {
  final double rating;
  final double demand;
  final double capacity;
  final double ceilingRevenue; // $/s once users catch up to min(demand, capacity)
  final double trainingSpeed; // effective training compute per second (relative)
  final double dataTokens;
  final double powerKw;

  ImpactSnapshot.of(Game g)
    : rating = g.rating,
      demand = g.demand,
      capacity = g.capacity,
      ceilingRevenue =
          revenueScale * math.pow(math.min(g.demand, g.capacity), revenueExponent) * g.arpuMult,
      trainingSpeed = g.trainingClusterTflops * g.trainEffMult,
      dataTokens = g.dataTokens,
      powerKw = g.powerUsedKw;
}

class ImpactLine {
  final IconData icon;
  final Color color;
  final String label;
  final String change; // "1.8k → 2.3k (+28%)"
  final String when; // "now" / "as users join" / "next model"
  const ImpactLine(this.icon, this.color, this.label, this.change, this.when);
}

List<ImpactLine> describeImpact(ImpactSnapshot a, ImpactSnapshot b) {
  String pct(double x, double y) {
    if (x <= 0) return '';
    final p = (y / x - 1) * 100;
    return ' (${p >= 0 ? '+' : ''}${p.abs() >= 10 ? p.round() : p.toStringAsFixed(1)}%)';
  }

  bool moved(double x, double y) => x > 0 ? (y / x - 1).abs() > 0.004 : y > 0;
  final out = <ImpactLine>[];

  if ((b.rating - a.rating).abs() >= 0.5) {
    out.add(ImpactLine(
      Icons.emoji_events_rounded,
      AppColors.amber,
      'Model rating',
      '${formatRating(a.rating)} → ${formatRating(b.rating)}',
      'now',
    ));
  }
  if (moved(a.demand, b.demand)) {
    out.add(ImpactLine(
      Icons.people_alt_rounded,
      AppColors.cyan,
      'User demand',
      '${formatNumber(a.demand)} → ${formatNumber(b.demand)}${pct(a.demand, b.demand)}',
      'users join over the next minutes',
    ));
  }
  if (moved(a.capacity, b.capacity)) {
    out.add(ImpactLine(
      Icons.dns_rounded,
      AppColors.cyan,
      'Serving capacity',
      '${formatNumber(a.capacity)} → ${formatNumber(b.capacity)}${pct(a.capacity, b.capacity)}',
      b.capacity > a.capacity && a.demand <= a.capacity
          ? 'only matters once demand exceeds capacity'
          : 'now',
    ));
  }
  if (moved(a.ceilingRevenue, b.ceilingRevenue)) {
    out.add(ImpactLine(
      Icons.attach_money_rounded,
      AppColors.neon,
      'Income ceiling',
      '${formatMoney(a.ceilingRevenue)}/s → ${formatMoney(b.ceilingRevenue)}/s'
          '${pct(a.ceilingRevenue, b.ceilingRevenue)}',
      'reached as users catch up',
    ));
  }
  if (moved(a.trainingSpeed, b.trainingSpeed)) {
    out.add(ImpactLine(
      Icons.model_training_rounded,
      AppColors.violet,
      'Training compute',
      '${pct(a.trainingSpeed, b.trainingSpeed).trim().replaceAll(RegExp(r'[()]'), '')} per second',
      'your next model comes out stronger',
    ));
  }
  if (moved(a.dataTokens, b.dataTokens)) {
    out.add(ImpactLine(
      Icons.menu_book_rounded,
      AppColors.violet,
      'Training data',
      '${formatNumber(a.dataTokens)} → ${formatNumber(b.dataTokens)} tokens',
      'bigger runs stop hitting the data wall',
    ));
  }
  if (moved(a.powerKw, b.powerKw)) {
    out.add(ImpactLine(
      Icons.bolt_rounded,
      AppColors.amber,
      'Power draw',
      '${formatPower(a.powerKw)} → ${formatPower(b.powerKw)}',
      b.powerKw < a.powerKw ? 'room for more GPUs' : 'now',
    ));
  }
  return out;
}

/// The body of the "Research complete" card.
class ImpactSummary extends StatelessWidget {
  final String blurb;
  final List<ImpactLine> lines;
  const ImpactSummary({super.key, required this.blurb, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Text(blurb, style: const TextStyle(color: AppColors.muted, height: 1.35)),
        const SizedBox(height: 14),
        Text('WHAT CHANGED', style: labelStyle(size: 10, color: AppColors.neon)),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          const Text(
            'Nothing visible yet: this pays off on your next training run.',
            style: TextStyle(fontSize: 13.5),
          ),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(l.icon, size: 18, color: l.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.label,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            child: Text(
                              l.change,
                              textAlign: TextAlign.right,
                              style: numStyle(size: 13, color: l.color),
                            ),
                          ),
                        ],
                      ),
                      Text(l.when, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHi,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Money comes from users. Users come from your model\'s rating and your '
            'serving capacity. Most research makes training better, so it shows '
            'up in \$/s after your next release.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}
