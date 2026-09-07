import 'package:flutter/material.dart';

/// Semantic colors resolved from the nearest Theme, never global mutable state.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
    required this.cardBorder,
    required this.navigationSurface,
    required this.onNavigation,
  });
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;
  final Color cardBorder;
  final Color navigationSurface;
  final Color onNavigation;
  static const light = AppPalette(
    background: Color(0xFFF7F4ED),
    surface: Color(0xFFFFFDF8),
    surfaceVariant: Color(0xFFEEF0E7),
    primary: Color(0xFF103D3C),
    primaryDark: Color(0xFF0B302E),
    primaryLight: Color(0xFF225C53),
    onPrimary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF103D3C),
    textSecondary: Color(0xFF536B64),
    divider: Color(0xFFB9C7BD),
    success: Color(0xFF256649),
    warning: Color(0xFF98410B),
    error: Color(0xFFAF3427),
    cardBorder: Color(0xFFCBD0C8),
    navigationSurface: Color(0xFF103D3C),
    onNavigation: Color(0xFFF7F4ED),
  );
  static const dark = AppPalette(
    background: Color(0xFF102421),
    surface: Color(0xFF172F2A),
    surfaceVariant: Color(0xFF213C34),
    primary: Color(0xFFA7DEC0),
    primaryDark: Color(0xFF75BFA4),
    primaryLight: Color(0xFFB5E5CD),
    onPrimary: Color(0xFF102D26),
    textPrimary: Color(0xFFE7EFE7),
    textSecondary: Color(0xFFABC1B4),
    divider: Color(0xFF466156),
    success: Color(0xFFA0D8B3),
    warning: Color(0xFFFFBF80),
    error: Color(0xFFFFB4A5),
    cardBorder: Color(0xFF3F5C4E),
    navigationSurface: Color(0xFF0B1D19),
    onNavigation: Color(0xFFE7EFE7),
  );
  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? primary,
    Color? primaryDark,
    Color? primaryLight,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? success,
    Color? warning,
    Color? error,
    Color? cardBorder,
    Color? navigationSurface,
    Color? onNavigation,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    primary: primary ?? this.primary,
    primaryDark: primaryDark ?? this.primaryDark,
    primaryLight: primaryLight ?? this.primaryLight,
    onPrimary: onPrimary ?? this.onPrimary,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    divider: divider ?? this.divider,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    cardBorder: cardBorder ?? this.cardBorder,
    navigationSurface: navigationSurface ?? this.navigationSurface,
    onNavigation: onNavigation ?? this.onNavigation,
  );
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      navigationSurface: Color.lerp(
        navigationSurface,
        other.navigationSurface,
        t,
      )!,
      onNavigation: Color.lerp(onNavigation, other.onNavigation, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get appColors {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}

abstract final class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light, AppPalette.light);
  static ThemeData get darkTheme => _build(Brightness.dark, AppPalette.dark);
  // Compatibility for existing render harnesses.
  static ThemeData get darkNavyTheme => darkTheme;
  static ThemeData _build(Brightness brightness, AppPalette c) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF103D3C),
          brightness: brightness,
        ).copyWith(
          primary: c.primary,
          onPrimary: c.onPrimary,
          primaryContainer: c.surfaceVariant,
          onPrimaryContainer: c.textPrimary,
          secondary: c.primaryLight,
          onSecondary: c.onPrimary,
          secondaryContainer: c.surfaceVariant,
          onSecondaryContainer: c.textPrimary,
          surface: c.surface,
          onSurface: c.textPrimary,
          onSurfaceVariant: c.textSecondary,
          surfaceContainerLowest: c.background,
          surfaceContainerLow: c.surface,
          surfaceContainer: c.surfaceVariant,
          surfaceContainerHigh: c.surfaceVariant,
          surfaceContainerHighest: c.surfaceVariant,
          outline: c.divider,
          outlineVariant: c.cardBorder,
          error: c.error,
          onError: dark ? c.background : Colors.white,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      extensions: [c],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
    );
    const buttonText = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary)
          .copyWith(
            headlineMedium: TextStyle(
              color: c.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
            headlineSmall: TextStyle(
              color: c.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
            titleLarge: TextStyle(
              color: c.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
            titleMedium: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: TextStyle(color: c.textPrimary, fontSize: 16),
            bodyMedium: TextStyle(color: c.textPrimary, fontSize: 14),
            bodySmall: TextStyle(color: c.textSecondary, fontSize: 12),
            labelLarge: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: TextStyle(color: c.textSecondary, fontSize: 12),
            labelSmall: TextStyle(color: c.textSecondary, fontSize: 12),
          )
          .apply(fontFamily: 'Roboto'),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: c.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        shape: Border(bottom: BorderSide(color: c.cardBorder)),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape.copyWith(side: BorderSide(color: c.cardBorder)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1),
      drawerTheme: DrawerThemeData(backgroundColor: c.surface),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.navigationSurface,
        selectedItemColor: const Color(0xFFFFC18C),
        unselectedItemColor: c.onNavigation,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: border(c.textSecondary),
        enabledBorder: border(c.textSecondary),
        focusedBorder: border(c.primary, 2),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, 2),
        labelStyle: TextStyle(color: c.textSecondary),
        hintStyle: TextStyle(color: c.textSecondary),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        helperMaxLines: 4,
        errorMaxLines: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          elevation: 0,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          side: BorderSide(color: c.divider),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primary,
        checkmarkColor: c.onPrimary,
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Roboto',
          color: c.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Roboto',
          color: c.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: c.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.navigationSurface,
        contentTextStyle: TextStyle(color: c.onNavigation),
        actionTextColor: const Color(0xFFFFC18C),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }
}
