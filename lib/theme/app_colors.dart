import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand and navigation.
  static const Color trailblazerOrange = Color(0xFFC65200);
  static const Color navigationNavy = Color(0xFF00335C);
  static const Color actionBlue = Color(0xFF005E85);

  // Backgrounds and cards.
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = white;
  static const Color orangeSurface = Color(0xFFFFF1E8);
  static const Color blueSurface = Color(0xFFEAF3F8);

  // Text.
  static const Color textBlue = navigationNavy;
  static const Color textPrimary = Color(0xFF172B3A);
  static const Color textSecondary = Color(0xFF526373);
  static const Color textOnDark = white;

  // Borders and feedback.
  static const Color border = Color(0xFFD5DEE6);
  static const Color success = Color(0xFF237A48);
  static const Color warning = Color(0xFF8A5700);
  static const Color error = Color(0xFFBA1A1A);

  // Nutrition charts.
  static const Color protein = actionBlue;
  static const Color carbohydrates = trailblazerOrange;
  static const Color fat = Color(0xFF7353A6);
}
