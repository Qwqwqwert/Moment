import 'package:flutter/material.dart';

ThemeData buildMomentTheme({bool desktop = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4267D6),
    brightness: Brightness.light,
    surface: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF7F8FC),
    fontFamilyFallback: desktop
        ? const [
            'Segoe UI',
            'Microsoft YaHei UI',
            'Microsoft YaHei',
            'sans-serif',
          ]
        : const ['Noto Sans SC', 'Microsoft YaHei', 'sans-serif'],
    visualDensity: desktop
        ? const VisualDensity(horizontal: -1, vertical: -1)
        : VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: const Color(0xFFF7F8FC),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      toolbarHeight: desktop ? 56 : null,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: desktop ? 20 : 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(desktop ? 8 : 20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: desktop ? 12 : 16,
        vertical: desktop ? 11 : 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(desktop ? 7 : 16),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: scheme.surface,
      selectedColor: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(desktop ? 6 : 12),
      ),
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 3,
      highlightElevation: 5,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const CircleBorder(),
    ),
  );
  if (!desktop) return base;
  return base.copyWith(
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    dialogTheme: DialogThemeData(
      elevation: 18,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? scheme.outline
            : scheme.outlineVariant,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(5),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
  );
}
