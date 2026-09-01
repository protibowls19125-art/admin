import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';

class ThemeConfigProvider extends ChangeNotifier {
  String _logoFontFamily = '';

  String get logoFontFamily => _logoFontFamily;

  Future<void> fetch() async {
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'logo_font_family')
          .maybeSingle();
      
      final val = res?['value'] as String?;
      if (val != null && val.trim().isNotEmpty) {
        _logoFontFamily = val.trim();
        notifyListeners();
      }
    } catch (_) {}
  }

  TextStyle getLogoStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double letterSpacing = 0,
    TextDecoration decoration = TextDecoration.none,
  }) {
    if (_logoFontFamily.isEmpty) {
      return GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    }
    try {
      return GoogleFonts.getFont(
        _logoFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    } catch (_) {
      return GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    }
  }
}
