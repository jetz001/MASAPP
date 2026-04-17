import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get _base => GoogleFonts.inter(color: AppColors.textPrimary);

  // Display
  static TextStyle get displayLarge => _base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static TextStyle get displayMedium => _base.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static TextStyle get displaySmall => _base.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2);

  // Headings
  static TextStyle get headlineLarge => _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600);
  static TextStyle get headlineMedium => _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle get headlineSmall => _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);

  // Title
  static TextStyle get titleLarge => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle get titleMedium => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w500);
  static TextStyle get titleSmall => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w500);

  // Body
  static TextStyle get bodyLarge => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  static TextStyle get bodyMedium => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get bodySmall => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);

  // Label
  static TextStyle get labelLarge => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.5);
  static TextStyle get labelMedium => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.4);
  static TextStyle get labelSmall => _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.6);

  // Mono
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
      color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w400);

  // Secondary text helpers
  static TextStyle get secondary => bodyMedium.copyWith(color: AppColors.textSecondary);
  static TextStyle get disabled => bodyMedium.copyWith(color: AppColors.textDisabled);
}
