import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Background Layers ──────────────────────────────────────────────────────
  static const Color bgBase = Color(0xFF0C0E14); // deeper richer slate
  static const Color bgSurface = Color(0xFF161926); // sophisticated navy-slate
  static const Color bgElevated = Color(0xFF1F2336); // refined elevation
  static const Color bgSidebar = Color(0xFF111422); // deep consistent sidebar

  // ── Brand / Primary ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF4F46E5); // premium indigo
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color primaryContainer = Color(0xFF312E81);

  // ── Status Colors ─────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981); // emerald
  static const Color successContainer = Color(0xFF064E3B);
  static const Color warning = Color(0xFFF59E0B); // amber
  static const Color warningContainer = Color(0xFF78350F);
  static const Color error = Color(0xFFEF4444); // rose-red
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color info = Color(0xFF0EA5E9); // sky blue

  // ── Machine Status ────────────────────────────────────────────────────────
  static const Color machineNormal = Color(0xFF10B981);
  static const Color machineBreakdown = Color(0xFFEF4444);
  static const Color machinePM = Color(0xFFF59E0B);
  static const Color machineAM = Color(0xFF8B5CF6); // violet
  static const Color machineOffline = Color(0xFF64748B); // slate

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF475569);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Borders / Dividers ────────────────────────────────────────────────────
  static const Color border = Color(0xFF262B3F);
  static const Color borderLight = Color(0xFF2D334D);
  static const Color divider = Color(0xFF1A1E2E);

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
