import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await loadThemeMode();
  runApp(const BaylockApp());
}

class BaylockApp extends StatelessWidget {
  const BaylockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'Baylock',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode, // varsayılan: telefonun ayarı
        home: const HomeScreen(),
      ),
    );
  }
}
