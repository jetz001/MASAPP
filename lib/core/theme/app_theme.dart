import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.info,
      onSecondary: AppColors.textOnPrimary,
      secondaryContainer: Color(0xFF164E63),
      onSecondaryContainer: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textOnPrimary,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.textPrimary,
      surface: AppColors.bgSurface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.bgElevated,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.borderLight,
      shadow: Color(0xFF000000),
      scrim: Color(0x80000000),
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.bgBase,
      inversePrimary: AppColors.primaryDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      fontFamily: GoogleFonts.inter().fontFamily,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgSidebar,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black38,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: AppColors.bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.all(0),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.bgElevated,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textDisabled),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        floatingLabelStyle:
            GoogleFonts.inter(fontSize: 12, color: AppColors.primary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // NavigationRail
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.bgSidebar,
        selectedIconTheme: const IconThemeData(color: AppColors.textOnPrimary, size: 22),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
        selectedLabelTextStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textOnPrimary),
        unselectedLabelTextStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
        indicatorColor: AppColors.primary,
        useIndicator: true,
        labelType: NavigationRailLabelType.all,
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgElevated,
        selectedColor: AppColors.primaryContainer,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),

      // Data Table
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.bgElevated),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return AppColors.navHover;
          return AppColors.bgSurface;
        }),
        headingTextStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        dataTextStyle:
            GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
        dividerThickness: 1,
        columnSpacing: 20,
        horizontalMargin: 16,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgSurface,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle:
            GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        contentTextStyle:
            GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.border),
        trackColor: WidgetStateProperty.all(AppColors.bgSurface),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(AppRadius.full),
      ),

      // PopupMenu
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        elevation: 8,
        textStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgElevated,
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: AppColors.navSelected,
        selectedColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.textOnPrimary),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.textOnPrimary;
          return AppColors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.bgElevated;
        }),
      ),

      // Tab Bar
      tabBarTheme: TabBarThemeData(
        indicatorColor: AppColors.primary,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400),
        dividerColor: AppColors.border,
      ),

      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.bgElevated,
      ),
    );
  }
}
