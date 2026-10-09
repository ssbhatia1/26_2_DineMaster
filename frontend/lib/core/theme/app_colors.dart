import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color navyBlue = Color(0xFF040E21); // Primary Navy
  static const Color gold = Color(0xFF946F3C); // Primary Gold
  static const Color background = Color(0xFFF8F9FA); // Clean light background
  static const Color white = Color(0xFFFFFFFF); // White
  
  // Neutral Tints based on Navy Blue
  static const Color navyBlue50 = Color(0xFFE6E8EB); 
  static const Color navyBlue100 = Color(0xFFBFC4CC);
  
  // Theme assignments
  static const Color primary = navyBlue;
  static const Color secondary = gold;
  static const Color accent = gold;
  
  static const Color primaryLight = navyBlue50;
  
  // Custom Material Color for primarySwatch
  static MaterialColor get primaryMaterialColor {
    return MaterialColor(navyBlue.value, <int, Color>{
      50: navyBlue50,
      100: navyBlue100,
      200: const Color(0xFF99A0AD),
      300: const Color(0xFF737C8F),
      400: const Color(0xFF4D5870),
      500: navyBlue,
      600: const Color(0xFF030C1E),
      700: const Color(0xFF030A1A),
      800: const Color(0xFF020712),
      900: const Color(0xFF01040A),
    });
  }
}
