import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const defaultAccentColor = Color(0xFF1E3A5F);
final accentColor = ValueNotifier<Color>(defaultAccentColor);
final appAppearance = Listenable.merge([themeMode, accentColor]);

/// Curated palettes. The selected seed drives the complete Material scheme.
enum AppPalette {
  ocean('Okyanus', Color(0xFF315A8A)),
  indigo('İndigo', Color(0xFF4F46E5)),
  forest('Orman', Color(0xFF26705C)),
  amber('Kehribar', Color(0xFFB45309)),
  rose('Gül', Color(0xFFBE3A5D)),
  plum('Erguvan', Color(0xFF7C3F9E));

  const AppPalette(this.label, this.seed);
  final String label;
  final Color seed;
}

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

  static Pal of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pal._(
      card: scheme.surfaceContainerLow,
      border: scheme.outlineVariant,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      headCell: scheme.surfaceContainerHighest,
      canvas: scheme.surfaceContainer,
      infoBox: scheme.secondaryContainer,
    );
  }
}

ThemeData buildTheme(Brightness b, {Color seedColor = defaultAccentColor}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );

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
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
