import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return FlexThemeData.light(
      scheme: FlexScheme.indigo,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 7,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        blendOnColors: false,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: true,
        defaultRadius: 10.0,
        thinBorderWidth: 1.0,
        thickBorderWidth: 2.0,
        inputDecoratorRadius: 10.0,
        inputDecoratorIsFilled: true,
        cardRadius: 14.0,
        popupMenuRadius: 10.0,
        dialogRadius: 16.0,
        appBarCenterTitle: false,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      swapLegacyOnMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
    );
  }

  static ThemeData get dark {
    return FlexThemeData.dark(
      colors: const FlexSchemeColor(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.info,
        secondaryContainer: Color(0xFF164E63),
        tertiary: Color(0xFF8B5CF6),
        tertiaryContainer: Color(0xFF4C1D95),
        appBarColor: AppColors.bgSidebar,
        error: AppColors.error,
      ),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 13,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: true,
        defaultRadius: 10.0,
        thinBorderWidth: 1.0,
        thickBorderWidth: 2.0,
        inputDecoratorRadius: 10.0,
        inputDecoratorIsFilled: true,
        cardRadius: 14.0,
        popupMenuRadius: 10.0,
        dialogRadius: 16.0,
        appBarCenterTitle: false,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      swapLegacyOnMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      scaffoldBackground: AppColors.bgBase,
    );
  }
}
