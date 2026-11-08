import 'package:baylock/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildTheme applies the selected accent in both brightness modes', () {
    const accent = Color(0xFF0F766E);

    expect(
      buildTheme(Brightness.light, seedColor: accent).colorScheme.primary,
      isNot(buildTheme(Brightness.light).colorScheme.primary),
    );
    expect(
      buildTheme(Brightness.dark, seedColor: accent).colorScheme.primary,
      isNot(buildTheme(Brightness.dark).colorScheme.primary),
    );
  });
}
