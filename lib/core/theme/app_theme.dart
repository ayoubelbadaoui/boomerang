import 'package:flutter/material.dart';

/// Centralized theme to keep typography and colors consistent across features.
ThemeData buildAppTheme() {
  const primaryTextColor = Color(0xFF111111);
  final base = ThemeData(
    fontFamily: 'Urbanist',
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF212121),
      primary: const Color(0xFF212121),
      onPrimary: Colors.white,
    ).copyWith(onSurface: const Color(0xFF212121)),
    useMaterial3: true,
  );

  final textTheme = base.textTheme
      .apply(
        fontFamily: 'Urbanist',
        bodyColor: primaryTextColor,
        displayColor: primaryTextColor,
      )
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      );

  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: textTheme,
  );
}
