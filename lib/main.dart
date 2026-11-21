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
    return AnimatedBuilder(
      animation: appAppearance,
      builder: (_, __) => MaterialApp(
        title: 'Baylock',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _TransientScrollbarBehavior(),
        themeAnimationDuration: Duration.zero,
        theme: buildTheme(Brightness.light, seedColor: accentColor.value),
        darkTheme: buildTheme(Brightness.dark, seedColor: accentColor.value),
        themeMode: themeMode.value,
        home: const HomeScreen(),
      ),
    );
  }
}

class _TransientScrollbarBehavior extends MaterialScrollBehavior {
  const _TransientScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: false,
      trackVisibility: false,
      child: child,
    );
  }
}
