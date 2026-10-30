import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const BaylockApp());
}

class BaylockApp extends StatelessWidget {
  const BaylockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baylock',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}