import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double full = 999.0;

  static BorderRadius get bxs => BorderRadius.circular(xs);
  static BorderRadius get bsm => BorderRadius.circular(sm);
  static BorderRadius get bmd => BorderRadius.circular(md);
  static BorderRadius get blg => BorderRadius.circular(lg);
  static BorderRadius get bxl => BorderRadius.circular(xl);
  static BorderRadius get bxxl => BorderRadius.circular(xxl);
  static BorderRadius get bfull => BorderRadius.circular(full);
}
