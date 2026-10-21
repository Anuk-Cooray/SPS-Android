// app_snackbar.dart
// Smart Parking (J26-IT-335) — themed snackbars. Info uses the black primary; warning (amber)
// and error (red) follow the colour rules in app_theme.dart and work in light and dark mode.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SnackTone { info, warning, error }

void showAppSnack(
  BuildContext context,
  String message, {
  SnackTone tone = SnackTone.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final c = context.colors;
  final background = switch (tone) {
    SnackTone.info => c.primary,
    SnackTone.warning => c.warning,
    SnackTone.error => c.danger,
  };
  // Pick black or white text by background brightness (dark-mode amber/red are light colours)
  final foreground = ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF0A0A0A);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppText.body.copyWith(color: foreground, fontWeight: FontWeight.w600),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
}
