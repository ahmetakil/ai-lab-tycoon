// OWNER: ui-core agent. "Terminal meets neon" dark theme.

import 'package:flutter/material.dart';

/// Palette. Use these instead of raw colours so the look stays consistent.
abstract final class AppColors {
  static const bg = Color(0xFF060A12);
  static const surface = Color(0xFF0C1320);
  static const surfaceHi = Color(0xFF111A2B);
  static const border = Color(0xFF1C2840);
  static const borderHi = Color(0xFF2A3A5A);
  static const text = Color(0xFFE6EDF7);
  static const muted = Color(0xFF8593AD);
  static const faint = Color(0xFF4A5875);

  static const neon = Color(0xFF39FF9F);
  static const cyan = Color(0xFF3BD8FF);
  static const amber = Color(0xFFFFB547);
  static const red = Color(0xFFFF4D6A);
  static const violet = Color(0xFFB07CFF);
}

const headingFont = 'SpaceGrotesk';
const monoFont = 'JetBrainsMono';
const _tabular = [FontFeature.tabularFigures()];

/// Monospace, tabular-figure style for numbers that change every tick.
TextStyle numStyle({
  double size = 14,
  Color color = AppColors.text,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: monoFont,
  fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'monospace'],
  fontFeatures: _tabular,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.15,
);

/// Small all-caps label ("COMPUTE", "TRAINING RUN").
TextStyle labelStyle({Color color = AppColors.muted, double size = 11}) => TextStyle(
  fontFamily: headingFont,
  fontSize: size,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
  color: color,
);

/// Max content width on wide (web/tablet) screens.
const maxContentWidth = 640.0;

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.neon,
    onPrimary: Color(0xFF00170C),
    secondary: AppColors.cyan,
    onSecondary: Color(0xFF001820),
    tertiary: AppColors.amber,
    error: AppColors.red,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surfaceHi,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: headingFont,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    dividerColor: AppColors.border,
    cardTheme: const CardTheme(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.neon.withValues(alpha: 0.14),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: headingFont,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: s.contains(WidgetState.selected) ? AppColors.neon : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.neon : AppColors.muted,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderHi)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.neon.withValues(alpha: 0.16)
                  : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.neon : AppColors.muted,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: monoFont, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.bg : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.neon : AppColors.surfaceHi,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: maxContentWidth),
    ),
    dialogTheme: const DialogTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: TextStyle(color: AppColors.text, fontFamily: headingFont),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHi,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
