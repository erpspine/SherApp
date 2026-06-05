import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_config.dart';

class SherTheme {
  // Sher Brand Colors
  static const Color sherGold = Color(kGoldColor); // #C9A961
  static const Color sherNavy = Color(kTealColor); // #1F3A4A
  static const Color sherRed = Color(kRedAccent); // #E63946
  static const Color darkBg = Color(kDarkBg);
  static const Color darkCard = Color(kDarkCard);
  static const Color darkBorder = Color(kDarkBorder);

  // Gradients
  static const LinearGradient sherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D2233), Color(kDarkBg), sherNavy],
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [sherGold, Color(0xFFC49A30)],
  );

  // Text Styles
  static TextStyle heading1 = GoogleFonts.inter(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w800,
  );

  static TextStyle heading2 = GoogleFonts.inter(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  static TextStyle heading3 = GoogleFonts.inter(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static TextStyle bodyLarge = GoogleFonts.inter(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static TextStyle bodySmall = GoogleFonts.inter(
    color: Colors.grey.shade300,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static TextStyle accentText = GoogleFonts.inter(
    color: sherRed,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // Box Shadows
  static BoxShadow goldShadow = BoxShadow(
    color: sherGold.withOpacity(0.4),
    blurRadius: 20,
    spreadRadius: 2,
  );

  static BoxShadow cardShadow = BoxShadow(
    color: Colors.black.withOpacity(0.3),
    blurRadius: 8,
    spreadRadius: 0,
  );

  // Material 3 Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: sherGold,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF3A3021),
        onPrimaryContainer: sherGold,
        secondary: sherNavy,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFF0D1F2A),
        onSecondaryContainer: Color(0xFF9ECAE1),
        tertiary: sherRed,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFF5A0A15),
        onTertiaryContainer: Color(0xFFFFB4A5),
        error: Color(0xFFFF6B6B),
        onError: Colors.white,
        errorContainer: Color(0xFF5A1515),
        onErrorContainer: Color(0xFFFFB4A5),
        background: darkBg,
        onBackground: Colors.white,
        surface: darkCard,
        onSurface: Colors.white,
        surfaceVariant: Color(0xFF2D3E4A),
        onSurfaceVariant: Color(0xFF94A3B8),
        outline: darkBorder,
        outlineVariant: Color(0xFF475569),
        scrim: Color(0x4D000000),
        inverseSurface: Color(0xFFE8EEF4),
        inversePrimary: sherGold,
      ),
      scaffoldBackgroundColor: darkBg,
      textTheme:
          GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme.apply(bodyColor: Colors.white),
          ).copyWith(
            displayLarge: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
            displayMedium: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
            displaySmall: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            headlineLarge: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            headlineMedium: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            headlineSmall: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            bodyMedium: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            bodySmall: GoogleFonts.inter(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
            labelLarge: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            labelSmall: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: darkBorder, width: 0.5),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: sherGold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
        prefixIconColor: const Color(0xFF64748B),
        suffixIconColor: const Color(0xFF64748B),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: sherGold,
          foregroundColor: Colors.white,
          disabledBackgroundColor: darkBorder,
          disabledForegroundColor: Color(0xFF64748B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          elevation: 0,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: sherGold,
          foregroundColor: Colors.white,
          disabledBackgroundColor: darkBorder,
          disabledForegroundColor: Color(0xFF64748B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: sherGold,
          disabledForegroundColor: darkBorder,
          side: const BorderSide(color: sherGold, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: sherGold,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: sherGold,
          disabledForegroundColor: darkBorder,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: darkBorder, width: 0.5),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkBorder,
        labelStyle: GoogleFonts.inter(color: Colors.white),
        selectedColor: sherGold,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: sherGold,
        linearMinHeight: 4,
      ),
    );
  }

  static ThemeData get lightTheme {
    const lightBg = Color(0xFFF3F4F6);
    const lightCard = Color(0xFFFFFFFF);
    const lightBorder = Color(0xFFD8DDE0);
    const heading = Color(0xFF2F5759);
    const body = Color(0xFF3D6668);
    const muted = Color(0xFF6D8A8B);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: sherGold,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFF5EBCF),
        onPrimaryContainer: Color(0xFF5F4A1B),
        secondary: sherNavy,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFDDE9E9),
        onSecondaryContainer: Color(0xFF1F3D3F),
        tertiary: sherRed,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFFE2E5),
        onTertiaryContainer: Color(0xFF7E1B22),
        error: Color(0xFFDC2626),
        onError: Colors.white,
        errorContainer: Color(0xFFFFE2E2),
        onErrorContainer: Color(0xFF7F1D1D),
        surface: lightCard,
        onSurface: heading,
        surfaceVariant: Color(0xFFF7F8F9),
        onSurfaceVariant: muted,
        outline: lightBorder,
        outlineVariant: Color(0xFFC7CED3),
        scrim: Color(0x4D000000),
      ),
      scaffoldBackgroundColor: lightBg,
      textTheme:
          GoogleFonts.interTextTheme(
            ThemeData.light().textTheme.apply(bodyColor: body),
          ).copyWith(
            displayLarge: GoogleFonts.inter(
              color: heading,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
            displayMedium: GoogleFonts.inter(
              color: heading,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
            displaySmall: GoogleFonts.inter(
              color: heading,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            headlineLarge: GoogleFonts.inter(
              color: heading,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            headlineMedium: GoogleFonts.inter(
              color: heading,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            headlineSmall: GoogleFonts.inter(
              color: heading,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: GoogleFonts.inter(
              color: heading,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            titleMedium: GoogleFonts.inter(
              color: heading,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: GoogleFonts.inter(
              color: heading,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: GoogleFonts.inter(
              color: body,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            bodyMedium: GoogleFonts.inter(
              color: body,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            bodySmall: GoogleFonts.inter(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
            labelLarge: GoogleFonts.inter(
              color: heading,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: GoogleFonts.inter(
              color: heading,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            labelSmall: GoogleFonts.inter(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightCard,
        foregroundColor: heading,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: heading,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: lightBorder, width: 0.7),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: sherGold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: sherGold,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: const Color(0xFF94A3B8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          elevation: 0,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: sherNavy,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: sherNavy,
          disabledForegroundColor: const Color(0xFF94A3B8),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: lightBorder, width: 0.7),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: heading,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5F9),
        labelStyle: GoogleFonts.inter(color: body),
        selectedColor: const Color(0xFFF6ECD6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: sherGold,
        linearMinHeight: 4,
      ),
    );
  }
}
