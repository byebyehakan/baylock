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

  test('custom palette also colours document surfaces', () {
    final ocean = buildTheme(
      Brightness.light,
      seedColor: AppPalette.ocean.seed,
    );
    final plum = buildTheme(
      Brightness.light,
      seedColor: AppPalette.plum.seed,
    );

    expect(ocean.colorScheme.primary, isNot(plum.colorScheme.primary));
    expect(
      ocean.colorScheme.surfaceContainerLow,
      isNot(plum.colorScheme.surfaceContainerLow),
    );
  });
}
