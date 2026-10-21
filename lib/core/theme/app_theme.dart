// app_theme.dart
// Smart Parking (J26-IT-335) — monochrome + one blue accent design system.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────────────────────
/// 1. COLOUR TOKENS
/// Rule: the accent means "yours" (your slot, selected pin, upgrade offer).
/// Primary buttons are black (white in dark mode), never the accent.
/// Amber only for the late-arrival warning. Red only for cancelled/errors.
/// ─────────────────────────────────────────────────────────────
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.warning,
    required this.warningSoft,
    required this.warningBorder,
    required this.danger,
    required this.slotFreeBorder,
    required this.slotTaken,
    required this.slotBlocked,
    required this.mapLand,
    required this.mapBlock,
    required this.mapRoad,
    required this.mapRoute,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary; // black button
  final Color onPrimary;
  final Color accent; // the ONE colour
  final Color accentSoft; // 10% accent fill (your slot)
  final Color warning; // late arrival only
  final Color warningSoft;
  final Color warningBorder;
  final Color danger;
  // Slot states (lot layout)
  final Color slotFreeBorder; // free = outlined
  final Color slotTaken; // taken = solid grey
  final Color slotBlocked; // blocked = hatched grey (draw stripes with this)
  // Map
  final Color mapLand;
  final Color mapBlock;
  final Color mapRoad;
  final Color mapRoute;

  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F4F5),
    border: Color(0xFFE4E4E7),
    divider: Color(0xFFF0F0F2),
    textPrimary: Color(0xFF0A0A0A),
    textSecondary: Color(0xFF66666F), // 5.7:1 on white, 5.2:1 on surfaceMuted
    textTertiary: Color(0xFF6E6E77), // 5.0:1 on white, 4.6:1 on surfaceMuted
    primary: Color(0xFF0A0A0A),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0x1A2563EB),
    warning: Color(0xFF92400E),
    warningSoft: Color(0xFFFFFBEB),
    warningBorder: Color(0xFFFDE68A),
    danger: Color(0xFFDC2626),
    slotFreeBorder: Color(0xFF85858D), // 3.7:1 — free slots must read as controls
    slotTaken: Color(0xFFD4D4D8),
    slotBlocked: Color(0xFFE4E4E7),
    mapLand: Color(0xFFEEEEF0),
    mapBlock: Color(0xFFE4E4E7),
    mapRoad: Color(0xFFFFFFFF),
    mapRoute: Color(0xFF0A0A0A),
  );

  static const dark = AppColors(
    background: Color(0xFF0B0B0C),
    surface: Color(0xFF161618),
    surfaceMuted: Color(0xFF1F1F23),
    border: Color(0xFF27272A),
    divider: Color(0xFF1F1F23),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFA1A1AA),
    textTertiary: Color(0xFF8E8E98), // 5.6:1 on surface
    primary: Color(0xFFFAFAFA),
    onPrimary: Color(0xFF0A0A0A),
    accent: Color(0xFF3B82F6),
    accentSoft: Color(0x263B82F6),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF2A1F0A),
    warningBorder: Color(0xFF5C4310),
    danger: Color(0xFFF87171),
    slotFreeBorder: Color(0xFF7A7A84), // 4.3:1 on surface
    slotTaken: Color(0xFF3F3F46),
    slotBlocked: Color(0xFF27272A),
    mapLand: Color(0xFF111113),
    mapBlock: Color(0xFF18181B),
    mapRoad: Color(0xFF27272A),
    mapRoute: Color(0xFF3B82F6),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? accentSoft,
    Color? warning,
    Color? warningSoft,
    Color? warningBorder,
    Color? danger,
    Color? slotFreeBorder,
    Color? slotTaken,
    Color? slotBlocked,
    Color? mapLand,
    Color? mapBlock,
    Color? mapRoad,
    Color? mapRoute,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      warningBorder: warningBorder ?? this.warningBorder,
      danger: danger ?? this.danger,
      slotFreeBorder: slotFreeBorder ?? this.slotFreeBorder,
      slotTaken: slotTaken ?? this.slotTaken,
      slotBlocked: slotBlocked ?? this.slotBlocked,
      mapLand: mapLand ?? this.mapLand,
      mapBlock: mapBlock ?? this.mapBlock,
      mapRoad: mapRoad ?? this.mapRoad,
      mapRoute: mapRoute ?? this.mapRoute,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      warningBorder: l(warningBorder, other.warningBorder),
      danger: l(danger, other.danger),
      slotFreeBorder: l(slotFreeBorder, other.slotFreeBorder),
      slotTaken: l(slotTaken, other.slotTaken),
      slotBlocked: l(slotBlocked, other.slotBlocked),
      mapLand: l(mapLand, other.mapLand),
      mapBlock: l(mapBlock, other.mapBlock),
      mapRoad: l(mapRoad, other.mapRoad),
      mapRoute: l(mapRoute, other.mapRoute),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// ─────────────────────────────────────────────────────────────
/// 2. SPACING & RADIUS (8 px grid)
/// ─────────────────────────────────────────────────────────────
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20; // screen side padding
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double chip = 6;
  static const double slot = 8;
  static const double cardSm = 10;
  static const double input = 14;
  static const double card = 16;
  static const double button = 16;
  static const double sheet = 24;
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetR =
      BorderRadius.vertical(top: Radius.circular(sheet));
}

abstract final class AppSize {
  static const double buttonHeight = 56;
  static const double inputHeight = 56;
  static const double iconButton = 48; // min touch target (Android 48dp)
}

/// Icon sizes: inline with caption text, standard UI icon, prominent/hero icon.
abstract final class AppIconSize {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOutCubic;
  static const Duration upgradeOfferTimeout = Duration(seconds: 60);
}

/// ─────────────────────────────────────────────────────────────
/// 3. TYPOGRAPHY — Manrope, two weights (400/600) + 700 for numbers.
/// Tabular figures everywhere numbers count (ETA, timers, fees).
/// ─────────────────────────────────────────────────────────────
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get _base => GoogleFonts.manrope(
        fontFeatures: _tabular,
        height: 1.35,
      );

  static TextStyle get display => _base.copyWith(
      fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.0); // ETA "12 min"
  static TextStyle get h1 => _base.copyWith(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.56, height: 1.15);
  static TextStyle get h2 => _base.copyWith(
      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4);
  static TextStyle get slotId => _base.copyWith(
      fontSize: 22, fontWeight: FontWeight.w700);
  static TextStyle get title => _base.copyWith(
      fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle get body => _base.copyWith(
      fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle get label => _base.copyWith(
      fontSize: 13, fontWeight: FontWeight.w600);
  static TextStyle get caption => _base.copyWith(
      fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle get overline => _base.copyWith(
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5);
  static TextStyle get button => _base.copyWith(
      fontSize: 16, fontWeight: FontWeight.w600);
}

/// ─────────────────────────────────────────────────────────────
/// 4. THEME DATA
/// ─────────────────────────────────────────────────────────────
abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.border,
      outlineVariant: c.divider,
    );

    final text = TextTheme(
      displaySmall: AppText.display.copyWith(color: c.textPrimary),
      headlineMedium: AppText.h1.copyWith(color: c.textPrimary),
      titleLarge: AppText.h2.copyWith(color: c.textPrimary),
      titleMedium: AppText.title.copyWith(color: c.textPrimary),
      bodyMedium: AppText.body.copyWith(color: c.textPrimary),
      bodySmall: AppText.caption.copyWith(color: c.textSecondary),
      labelLarge: AppText.button,
      labelMedium: AppText.label.copyWith(color: c.textSecondary),
    );

    final roundedBtn = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button));

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      textTheme: text,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),

      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.h2.copyWith(color: c.textPrimary),
      ),

      // Primary = black (white in dark). Full width, 56 high.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size.fromHeight(AppSize.buttonHeight),
          shape: roundedBtn,
          textStyle: AppText.button,
          elevation: 0,
        ),
      ),
      // Secondary = 1px border.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: c.border),
          shape: roundedBtn,
          textStyle: AppText.button.copyWith(fontSize: 15),
        ),
      ),
      // Tertiary = text only (e.g. "Keep A-06", "Cancel").
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(44, 44),
          textStyle: AppText.button.copyWith(fontSize: 15),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: AppText.body.copyWith(color: c.textTertiary),
        labelStyle: AppText.label.copyWith(color: c.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: c.textPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: c.danger),
        ),
      ),

      // Cards: flat, 1px border, no shadow.
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardR,
          side: BorderSide(color: c.border),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.slotTaken,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetR),
        modalBarrierColor: Colors.black.withValues(alpha: 0.4),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            AppText.caption.copyWith(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: s.contains(WidgetState.selected)
                  ? c.textPrimary
                  : c.textSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected)
                  ? c.textPrimary
                  : c.textSecondary,
            )),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.primary : c.border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.divider,
        circularTrackColor: c.divider,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.primary,
        contentTextStyle: AppText.body.copyWith(color: c.onPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// 5. SLOT STATE HELPER (lot layout on Book Slot screen)
/// ─────────────────────────────────────────────────────────────
enum SlotState { free, taken, blocked, yours }

class SlotStyle {
  const SlotStyle({this.fill, this.border, required this.label});
  final Color? fill;
  final BorderSide? border;
  final Color label;

  static SlotStyle of(SlotState s, AppColors c) => switch (s) {
        SlotState.free => SlotStyle(
            fill: c.surface,
            border: BorderSide(color: c.slotFreeBorder, width: 1.5),
            label: c.textSecondary),
        SlotState.taken =>
          SlotStyle(fill: c.slotTaken, label: c.textSecondary),
        SlotState.blocked =>
          SlotStyle(fill: c.slotBlocked, label: c.textTertiary), // + stripes
        SlotState.yours => SlotStyle(
            fill: c.accentSoft,
            border: BorderSide(color: c.accent, width: 2),
            label: c.accent),
      };
}

/// ─────────────────────────────────────────────────────────────
/// 6. GOOGLE MAPS — grayscale style (pass to GoogleMap(style: ...)).
/// ─────────────────────────────────────────────────────────────
abstract final class AppMapStyle {
  static const light = '''
[
  {"elementType":"geometry","stylers":[{"color":"#eeeef0"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#71717a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e4e4e7"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e4e4e7"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#d4d4d8"}]}
]''';

  static const dark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#111113"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#71717a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0b0c"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#27272a"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3f3f46"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#18181b"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#09090b"}]}
]''';
}
