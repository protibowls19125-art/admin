import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Epicurean Minimalist — "Modern Bistro" design system.
///
/// Sophisticated, clean and appetizing: an ivory base, rich charcoal text,
/// and a vibrant green accent reserved for actions and prices, with tangerine
/// yellow highlights. Editorial serif (Playfair Display) for dish names /
/// headlines, Inter for everything functional. Rounded shapes, soft shadows.
///
/// NOTE: the class keeps the historical name `BauhausTheme` so the existing
/// ~250 call sites keep working; the colour roles below have been remapped to
/// the new palette.
class BauhausTheme {
  // ── Core palette (semantic roles; legacy names preserved) ──────────────────
  /// Rich charcoal — primary text, headings, dark UI elements.
  static const Color primaryBlack = Color(0xFF1B1C1C);

  /// Near-black — highest-contrast surfaces (e.g. floating cart bar).
  static const Color surfaceBlack = Color(0xFF0A0A0A);

  /// Pure white — card surfaces and text/icons on the accent.
  static const Color white = Color(0xFFFFFFFF);

  /// Ivory — the app background ("menu paper").
  static const Color background = Color(0xFFFAF5E9);

  /// Subtle filled areas — search field, image placeholders, low containers.
  static const Color lightGrey = Color(0xFFF5F3F3);

  /// Neutral container — chips / pills (e.g. "Table 12").
  static const Color surfaceContainer = Color(0xFFEFEDED);

  /// Slightly stronger neutral container — dietary tag chips.
  static const Color surfaceContainerHigh = Color(0xFFE9E8E7);

  /// Secondary text — descriptions, captions, inactive nav.
  static const Color mediumGrey = Color(0xFF707070);

  /// On-surface variant (design token) — descriptions, idle nav, chips.
  static const Color onSurfaceVariant = Color(0xFF444748);

  /// Green accent — call-to-action buttons, prices, highlights.
  static const Color accentRed = Color(0xFF007A3D);

  /// Tangerine yellow — secondary accent, badges, highlights.
  static const Color accentYellow = Color(0xFFFFCC00);

  /// Soft green — accent badges / subtle accent fills.
  static const Color accentSoft = Color(0xFF4DC080);

  /// Hairline dividers between list items.
  static const Color patternGrey = Color(0xFFEDEDED);

  /// Borders / outlines.
  static const Color outline = Color(0xFFC4C7C7);

  /// Text/icon colour that always reads on top of [accentRed].
  static const Color onAccent = Color(0xFFFFFFFF);

  static const Color error = Color(0xFFBA1A1A);

  // ── Shape & elevation tokens ───────────────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 999;

  /// Soft ambient shadow for resting cards ("paper on table").
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  /// Stronger shadow for floating / high-priority surfaces.
  static List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ];

  // ── Typography helpers ─────────────────────────────────────────────────────
  /// Editorial serif — dish names, section titles, hero headlines.
  static TextStyle heading(
          {double size = 24, FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: weight,
        color: color ?? primaryBlack,
        height: 1.2,
      );

  /// Functional sans — body, labels, prices.
  static TextStyle body(
          {double size = 16,
          FontWeight weight = FontWeight.w400,
          Color? color,
          double? spacing,
          double? height}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color ?? primaryBlack,
        letterSpacing: spacing,
        height: height,
      );

  static ThemeData get theme {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      primaryColor: accentRed,
      colorScheme: const ColorScheme.light(
        primary: accentRed,
        onPrimary: onAccent,
        secondary: accentRed,
        onSecondary: onAccent,
        surface: white,
        onSurface: primaryBlack,
        surfaceContainerHighest: surfaceContainerHigh,
        outline: outline,
        error: error,
        onError: Colors.white,
      ),
      textTheme: _textTheme(base.textTheme),
      iconTheme: const IconThemeData(color: primaryBlack),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: primaryBlack,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: primaryBlack),
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: primaryBlack,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentRed,
          foregroundColor: onAccent,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlack,
          side: const BorderSide(color: primaryBlack, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentRed,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accentRed, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: mediumGrey,
          letterSpacing: 0.3,
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: mediumGrey,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainerHigh,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: mediumGrey,
        ),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: white,
        selectedItemColor: accentRed,
        unselectedItemColor: mediumGrey,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerColor: patternGrey,
      dividerTheme: const DividerThemeData(
        color: patternGrey,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    final playfair = GoogleFonts.playfairDisplayTextTheme(base);
    final inter = GoogleFonts.interTextTheme(base);
    return base.copyWith(
      // Editorial serif headlines
      headlineLarge: playfair.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: primaryBlack,
        height: 1.2,
      ),
      headlineMedium: playfair.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: primaryBlack,
        height: 1.3,
      ),
      headlineSmall: playfair.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primaryBlack,
      ),
      titleLarge: inter.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primaryBlack,
      ),
      // Functional sans body
      bodyLarge: inter.bodyLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: primaryBlack,
        height: 1.6,
      ),
      bodyMedium: inter.bodyMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: primaryBlack,
        height: 1.5,
      ),
      bodySmall: inter.bodySmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: mediumGrey,
        height: 1.5,
      ),
      labelLarge: inter.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primaryBlack,
        letterSpacing: 0.7,
      ),
    );
  }
}
