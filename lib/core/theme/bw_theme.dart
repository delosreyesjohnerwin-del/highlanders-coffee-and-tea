import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bw_colors.dart';
import 'bw_metrics.dart';

/// Assembles the app-wide [ThemeData] from the monochrome tokens.
///
/// Typography carries most of the visual weight here: strong black headings
/// against muted #666666 body copy, with generous letter-spacing on the small
/// uppercase labels that give the layout its editorial feel.
class BwTheme {
  const BwTheme._();

  static const String _fontFamily = 'Roboto';

  static ThemeData build() {
    const ColorScheme scheme = ColorScheme.light(
      primary: BwColors.inverse,
      onPrimary: BwColors.onInverse,
      primaryContainer: BwColors.subtle,
      onPrimaryContainer: BwColors.text,
      secondary: BwColors.inverse,
      onSecondary: BwColors.onInverse,
      surface: BwColors.surface,
      onSurface: BwColors.text,
      surfaceContainerHighest: BwColors.subtle,
      outline: BwColors.border,
      outlineVariant: BwColors.border,
      // Deliberately monochrome: validation states are signalled by an icon
      // and a border rather than by hue.
      error: BwColors.text,
      onError: BwColors.onInverse,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: BwColors.bg,
      fontFamily: _fontFamily,
      splashFactory: InkSparkle.splashFactory,
    );

    final TextTheme text = _textTheme(base.textTheme);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      dividerColor: BwColors.border,
      dividerTheme: const DividerThemeData(
        color: BwColors.border,
        thickness: BwStroke.hairline,
        space: BwStroke.hairline,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BwColors.bg,
        foregroundColor: BwColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: BwColors.text,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: BwColors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: BwColors.bg,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      filledButtonTheme: _filledButtonTheme(),
      outlinedButtonTheme: _outlinedButtonTheme(),
      textButtonTheme: _textButtonTheme(),
      iconButtonTheme: _iconButtonTheme(),
      inputDecorationTheme: _inputDecorationTheme(),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BwColors.surface,
        surfaceTintColor: BwColors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(BwRadius.card)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: BwColors.inverse,
        contentTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: BwColors.onInverse,
        ),
        actionTextColor: BwColors.onInverse,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(BwRadius.card)),
        ),
      ),
      chipTheme: _chipTheme(),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BwColors.inverse,
        linearTrackColor: BwColors.subtle,
        circularTrackColor: BwColors.subtle,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: BwColors.surface,
        surfaceTintColor: BwColors.transparent,
        indicatorColor: BwColors.subtle,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(BwColors.onInverse),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? BwColors.inverse : BwColors.subtle),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(BwColors.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? BwColors.inverse : BwColors.transparent),
        checkColor: const WidgetStatePropertyAll<Color>(BwColors.onInverse),
        side: const BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BwRadius.chip)),
      ),
      splashColor: const Color(0x0A000000),
      highlightColor: const Color(0x0A000000),
      hoverColor: const Color(0x05000000),
      focusColor: const Color(0x0F000000),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    TextStyle t(double size, FontWeight weight, Color color, {double? height, double? spacing}) {
      return TextStyle(
        fontFamily: _fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );
    }

    return base.copyWith(
      displayLarge: t(34, FontWeight.w800, BwColors.text, spacing: -0.8),
      displayMedium: t(28, FontWeight.w800, BwColors.text, spacing: -0.6),
      displaySmall: t(24, FontWeight.w700, BwColors.text, spacing: -0.4),
      headlineLarge: t(24, FontWeight.w800, BwColors.text, spacing: -0.4),
      headlineMedium: t(21, FontWeight.w700, BwColors.text, spacing: -0.3),
      headlineSmall: t(18, FontWeight.w700, BwColors.text, spacing: -0.2),
      titleLarge: t(17, FontWeight.w700, BwColors.text, spacing: -0.2),
      titleMedium: t(15, FontWeight.w600, BwColors.text, spacing: -0.1),
      titleSmall: t(14, FontWeight.w600, BwColors.text),
      bodyLarge: t(15, FontWeight.w400, BwColors.text, height: 1.45),
      bodyMedium: t(14, FontWeight.w400, BwColors.textMuted, height: 1.45),
      bodySmall: t(13, FontWeight.w400, BwColors.textMuted, height: 1.4),
      labelLarge: t(14, FontWeight.w600, BwColors.text),
      labelMedium: t(12, FontWeight.w600, BwColors.textMuted),
      labelSmall: t(11, FontWeight.w700, BwColors.textMuted, spacing: 0.8),
    );
  }

  static FilledButtonThemeData _filledButtonTheme() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BwColors.inverse,
        foregroundColor: BwColors.onInverse,
        disabledBackgroundColor: BwColors.disabledBg,
        disabledForegroundColor: BwColors.disabled,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(BwRadius.card)),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BwColors.text,
        backgroundColor: BwColors.subtle,
        disabledForegroundColor: BwColors.disabled,
        disabledBackgroundColor: BwColors.subtle,
        minimumSize: const Size.fromHeight(50),
        elevation: 0,
        side: const BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(BwRadius.card)),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BwColors.text,
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.sm, vertical: BwSpacing.sm),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static IconButtonThemeData _iconButtonTheme() {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: BwColors.text,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(BwRadius.chip)),
        ),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme() {
    const OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(BwRadius.field)),
      borderSide: BorderSide(color: BwColors.border, width: BwStroke.hairline),
    );

    return const InputDecorationTheme(
      filled: true,
      fillColor: BwColors.bg,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: BwColors.textMuted,
      ),
      labelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: BwColors.textMuted,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: BwColors.text,
      ),
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(BwRadius.field)),
        borderSide: BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(BwRadius.field)),
        borderSide: BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(BwRadius.field)),
        borderSide: BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
      ),
      errorStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: BwColors.text,
      ),
      prefixIconColor: BwColors.textMuted,
      suffixIconColor: BwColors.textMuted,
      border: border,
    );
  }

  static ChipThemeData _chipTheme() {
    return const ChipThemeData(
      backgroundColor: BwColors.bg,
      selectedColor: BwColors.inverse,
      disabledColor: BwColors.subtle,
      labelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: BwColors.text,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: BwColors.onInverse,
      ),
      side: BorderSide(color: BwColors.borderStrong, width: BwStroke.strong),
      shape: StadiumBorder(),
      showCheckmark: false,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }
}