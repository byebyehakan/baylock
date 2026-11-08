import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const defaultAccentColor = Color(0xFF1E3A5F);
final accentColor = ValueNotifier<Color>(defaultAccentColor);
final appAppearance = Listenable.merge([themeMode, accentColor]);

Future<void> loadThemeMode() async {
  final sp = await SharedPreferences.getInstance();
  themeMode.value = switch (sp.getString('theme_mode')) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  accentColor.value = Color(
    sp.getInt('accent_color') ?? defaultAccentColor.toARGB32(),
  );
}

Future<void> setThemeMode(ThemeMode m) async {
  themeMode.value = m;
  final sp = await SharedPreferences.getInstance();
  await sp.setString('theme_mode', m.name);
}

Future<void> setAccentColor(Color color) async {
  accentColor.value = color;
  final sp = await SharedPreferences.getInstance();
  await sp.setInt('accent_color', color.toARGB32());
}

/// Elle yazılmış renklerin yerine geçen palet.
class Pal {
  final Color card, border, text, muted, headCell, canvas, infoBox;
  const Pal._({
    required this.card,
    required this.border,
    required this.text,
    required this.muted,
    required this.headCell,
    required this.canvas,
    required this.infoBox,
  });

  static const light = Pal._(
    card: Colors.white,
    border: Color(0xFFE2E6EC),
    text: Color(0xFF14202F),
    muted: Color(0xFF5A6B7F),
    headCell: Color(0xFFEEF1F5),
    canvas: Color(0xFFE9ECF1),
    infoBox: Color(0xFFEAF1FB),
  );

  static const dark = Pal._(
    card: Color(0xFF1C2530),
    border: Color(0xFF2E3946),
    text: Color(0xFFE6EBF1),
    muted: Color(0xFF9AA8B8),
    headCell: Color(0xFF242F3B),
    canvas: Color(0xFF0F141A),
    infoBox: Color(0xFF1B2A3D),
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b, {Color seedColor = defaultAccentColor}) {
  final isDark = b == Brightness.dark;
  final pal = isDark ? Pal.dark : Pal.light;

  var scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: b);
  scheme = isDark
      ? scheme.copyWith(surface: const Color(0xFF12171D))
      : scheme.copyWith(surface: const Color(0xFFF6F7F9));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: pal.text,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
