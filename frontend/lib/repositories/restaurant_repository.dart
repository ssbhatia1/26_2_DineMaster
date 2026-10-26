
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_mode.dart';
import '../core/database/database_helper.dart';
import '../services/backend_api_client.dart';
import '../services/sync_service.dart';

class RestaurantRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final BackendApiClient _apiClient;

  RestaurantRepository({
    BackendApiClient apiClient = const BackendApiClient(),
  }) : _apiClient = apiClient;

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getRestaurants() async {
    if (await _useBackendApi()) {
      final response = await _apiClient.getJson('/api/restaurants');

      if (response is! List) {
        throw const FormatException(
          'Expected a restaurant list from the backend',
        );
      }

      return response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }

    // Offline: read from local SQLite
    final db = await _dbHelper.database;

    return db.query(
      'restaurants',
      orderBy: 'id ASC',
    );
  }

  // ---------------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------------

  /// Creates a new restaurant. Returns the new record's id.
  Future<int> createRestaurant({
    required String name,
    String? address,
    String? phone,
  }) async {
    if (await _useBackendApi()) {
      final response = await _apiClient.postJson('/api/restaurants', {
        'name': name,
        if (address != null && address.isNotEmpty) 'address': address,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });

      final id = (response['id'] as num).toInt();

      SyncService.instance.broadcastEvent('database_update', {
        'action': 'add_restaurant',
        'restaurantId': id,
      });

      return id;
    }

    // Offline: insert into local SQLite
    final db = await _dbHelper.database;

    final id = await db.insert('restaurants', {
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      'created_at': DateTime.now().toIso8601String(),
    });

    SyncService.instance.broadcastEvent('database_update', {
      'action': 'add_restaurant',
      'restaurantId': id,
    });

    return id;
  }

  // ---------------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------------

  /// Updates name/address/phone of an existing restaurant by [id].
  Future<void> updateRestaurant({
    required int id,
    required String name,
    String? address,
    String? phone,
  }) async {
    if (await _useBackendApi()) {
      await _apiClient.putJson('/api/restaurants/$id', {
        'name': name,
        'address': address,
        'phone': phone,
      });

      SyncService.instance.broadcastEvent('database_update', {
        'action': 'update_restaurant',
        'restaurantId': id,
      });

      return;
    }

    // Offline: update local SQLite
    final db = await _dbHelper.database;

    await db.update(
      'restaurants',
      {
        'name': name,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.broadcastEvent('database_update', {
      'action': 'update_restaurant',
      'restaurantId': id,
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  /// Deletes a restaurant by [id]. Returns number of rows affected (SQLite)
  /// or 1 on success (API).
  Future<int> deleteRestaurant(int id) async {
    if (await _useBackendApi()) {
      await _apiClient.delete('/api/restaurants/$id');

      SyncService.instance.broadcastEvent('database_update', {
        'action': 'delete_restaurant',
        'restaurantId': id,
      });

      return 1;
    }

    // Offline: delete from local SQLite
    final db = await _dbHelper.database;

    final count = await db.delete(
      'restaurants',
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.broadcastEvent('database_update', {
      'action': 'delete_restaurant',
      'restaurantId': id,
    });

    return count;
  }

  // ---------------------------------------------------------------------------
  // CHILD RECORD COUNT (for delete cascade warning)
  // ---------------------------------------------------------------------------

  /// Returns counts of linked child records for a restaurant.
  /// Only meaningful on the offline (SQLite) path.
  Future<Map<String, int>> getLinkedRecordCounts(int restaurantId) async {
    if (await _useBackendApi()) {
      // Backend enforces cascades; return empty map to skip client-side warning.
      return {};
    }

    final db = await _dbHelper.database;

    Future<int> count(String table) async {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $table WHERE restaurant_id = ?',
        [restaurantId],
      );

      return (result.first['c'] as int?) ?? 0;
    }

    return {
      'tables': await count('tables'),
      'products': await count('products'),
      'orders': await count('orders'),
    };
  }

  // ---------------------------------------------------------------------------
  // MODE HELPER
  // ---------------------------------------------------------------------------

  Future<bool> _useBackendApi() async {
    final prefs = await SharedPreferences.getInstance();

    return kIsWeb ||
        (prefs.getBool('use_backend_api') ??
            ApiMode.defaultUseBackendApi);
  }
}

