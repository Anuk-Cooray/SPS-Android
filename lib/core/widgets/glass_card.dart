// glass_card.dart
// Smart Parking (J26-IT-335) — translucent "glass" surface for the dark premium look.

import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A frosted card: translucent navy fill, hairline light border, optional background blur
/// (use [blur] only over busy content such as the map — it costs GPU time) and an optional
/// accent glow for the selected item.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.radius = AppRadius.card,
    this.blur = false,
    this.selected = false,
    this.glowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final bool selected;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(radius);
    final glow = glowColor ?? c.accent;

    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.06), c.surface.withValues(alpha: blur ? 0.72 : 1)),
            c.surface.withValues(alpha: blur ? 0.66 : 1),
          ],
        ),
        border: Border.all(
          color: selected ? glow.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.08),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: child,
    );

    if (blur) {
      body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: body);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: selected
            ? AppEffects.glow(glow, strength: 0.35, blur: 22)
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}

/// Glass styling for existing containers: translucent gradient fill, hairline border, soft depth.
/// [highlight] adds an accent border and glow (recommended item, active booking, your slot).
BoxDecoration glassDecoration(AppColors c, {bool highlight = false, double radius = AppRadius.card, Color? glowColor}) {
  final glow = glowColor ?? c.accent;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(Colors.white.withValues(alpha: 0.05), c.surface), c.surface],
    ),
    border: Border.all(
      color: highlight ? glow.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
      width: highlight ? 1.4 : 1,
    ),
    boxShadow: highlight
        ? AppEffects.glow(glow, strength: 0.28, blur: 26)
        : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
  );
}
