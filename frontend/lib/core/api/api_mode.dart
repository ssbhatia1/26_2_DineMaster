import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiMode {
  /// Canonical default for the 'use_backend_api' preference.
  /// false = SQLite (offline/LAN), true = Spring REST backend.
  /// All repositories must use this constant as their fallback default.
  static const bool defaultUseBackendApi = false;

  static Future<bool> useBackendApi() async {
    if (kIsWeb) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('use_backend_api') ?? defaultUseBackendApi;
  }

  static Future<void> setCurrentRestaurantId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_restaurant_id', id);
  }

  static Future<int?> currentRestaurantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('current_restaurant_id');
  }
}

class RoleNames {
  static String canonical(String role) {
    final value = role.trim().toUpperCase().replaceAll(' ', '_');
    final normalized = value.startsWith('ROLE_') ? value.substring(5) : value;
    switch (normalized) {
      case 'OWNER':
      case 'MANAGER':
      case 'CASHIER':
      case 'WAITER':
      case 'CHEF':
      case 'STAFF':
        return normalized;
      case 'COOK':
        return 'CHEF';
      case 'EMPLOYEE':
        return 'STAFF';
      default:
        return normalized;
    }
  }

  static bool matches(String actual, String selected) {
    return canonical(actual) == canonical(selected);
  }
}
