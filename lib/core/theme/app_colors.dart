import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Background Layers ──────────────────────────────────────────────────────
  static const Color bgBase = Color(0xFF0F1117); // deepest background
  static const Color bgSurface = Color(0xFF1A1D2E); // card / panel
  static const Color bgElevated = Color(0xFF242840); // elevated card
  static const Color bgSidebar = Color(0xFF141727); // sidebar rail

  // ── Brand / Primary ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF2563EB); // industrial blue
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryContainer = Color(0xFF1E3A8A);

  // ── Status Colors ─────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981); // healthy green
  static const Color successContainer = Color(0xFF064E3B);
  static const Color warning = Color(0xFFF59E0B); // PM/AM amber
  static const Color warningContainer = Color(0xFF78350F);
  static const Color error = Color(0xFFEF4444); // breakdown red
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color info = Color(0xFF06B6D4); // info cyan

  // ── Machine Status ────────────────────────────────────────────────────────
  static const Color machineNormal = Color(0xFF10B981);
  static const Color machineBreakdown = Color(0xFFEF4444);
  static const Color machinePM = Color(0xFFF59E0B);
  static const Color machineAM = Color(0xFF8B5CF6);
  static const Color machineOffline = Color(0xFF64748B);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF475569);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Borders / Dividers ────────────────────────────────────────────────────
  static const Color border = Color(0xFF2D3348);
  static const Color borderLight = Color(0xFF374151);
  static const Color divider = Color(0xFF1E2235);

  // ── Sidebar / Navigation ──────────────────────────────────────────────────
  static const Color navRail = Color(0xFF141727);
  static const Color navSelected = Color(0xFF1E3A8A);
  static const Color navHover = Color(0xFF1E2235);

  // ── Severity Badges ───────────────────────────────────────────────────────
  static const Color severityCritical = Color(0xFFEF4444);
  static const Color severityHigh = Color(0xFFF97316);
  static const Color severityMedium = Color(0xFFF59E0B);
  static const Color severityLow = Color(0xFF10B981);

  // ── Chart Palette ─────────────────────────────────────────────────────────
  static const List<Color> chartPalette = [
    Color(0xFF2563EB),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFF97316),
    Color(0xFFEC4899),
  ];
}
