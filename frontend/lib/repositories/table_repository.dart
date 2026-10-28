
import '../core/api/api_mode.dart';
import '../core/database/database_helper.dart';
import '../models/table_model.dart';
import '../services/backend_api_client.dart';
import '../services/sync_service.dart';

class TableRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final BackendApiClient _apiClient = const BackendApiClient();

  Future<bool> _useBackendApi() => ApiMode.useBackendApi();

  Future<List<TableModel>> getTables() async {
    if (await _useBackendApi()) {
      final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;
      final response = await _apiClient.getJson(
        '/api/tables?restaurantId=$restaurantId',
      );
      return _parseTables(response);
    }

    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;

    final maps = await db.rawQuery(
      '''
      SELECT t.*, u.name AS waiter_name
      FROM tables t
      LEFT JOIN users u ON t.waiter_id = u.id
      WHERE (t.restaurant_id = ? OR t.restaurant_id IS NULL)
      ORDER BY t.table_number ASC
      ''',
      [restaurantId],
    );

    return maps.map((map) => TableModel.fromMap(map)).toList();
  }

  Future<int> addTable(TableModel table) async {
    if (await _useBackendApi()) {
      final response = await _apiClient.postJson(
        '/api/tables',
        _toApiMap(table),
      );
      final id = response['id'];
      if (id is! num) {
        throw const FormatException(
          'Backend did not return a valid table ID',
        );
      }
      return id.toInt();
    }

    final db = await _dbHelper.database;
    final map = table.toMap()
      ..remove('waiter_name')
      ..remove('id');

    map['restaurant_id'] =
        table.restaurantId ?? DatabaseHelper.currentRestaurantId ?? 1;

    final id = await db.insert('tables', map);

    SyncService.instance.broadcastEvent(
      'database_update',
      {'action': 'add_table', 'tableId': id},
    );

    return id;
  }

  Future<int> updateTable(TableModel table) async {
    if (await _useBackendApi()) {
      final id = table.id;
      if (id == null) {
        throw ArgumentError('Table ID is required for update');
      }

      await _apiClient.putJson('/api/tables/$id', _toApiMap(table));
      return 1;
    }

    final id = table.id;
    if (id == null) {
      throw ArgumentError('Table ID is required for update');
    }

    final db = await _dbHelper.database;
    final map = table.toMap()
      ..remove('waiter_name');

    map['restaurant_id'] =
        table.restaurantId ?? DatabaseHelper.currentRestaurantId ?? 1;

    final count = await db.update(
      'tables',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.broadcastEvent(
      'database_update',
      {'action': 'update_table', 'tableId': id},
    );

    return count;
  }

  Future<int> deleteTable(int id) async {
    if (await _useBackendApi()) {
      await _apiClient.delete('/api/tables/$id');
      return 1;
    }

    final db = await _dbHelper.database;
    final count = await db.delete(
      'tables',
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.broadcastEvent(
      'database_update',
      {'action': 'delete_table', 'tableId': id},
    );

    return count;
  }

  Future<int> updateTableStatus(int id, String status) async {
    if (await _useBackendApi()) {
      // Reuse the existing GET and PUT APIs, preserving other table fields.
      final response = await _apiClient.getJson('/api/tables/$id');
      if (response is! Map) {
        throw const FormatException('Invalid table response from backend');
      }

      final table = TableModel.fromMap(
        Map<String, dynamic>.from(response),
      );

      await _apiClient.putJson(
        '/api/tables/$id',
        _toApiMap(table.copyWith(status: status)),
      );

      return 1;
    }

    final db = await _dbHelper.database;
    final count = await db.update(
      'tables',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.broadcastEvent(
      'database_update',
      {
        'action': 'update_status',
        'tableId': id,
        'status': status,
      },
    );

    return count;
  }

  /// SQLite order reconciliation is available only on desktop/mobile.
  /// Web order and booking reconciliation should be handled by the backend.
  Future<void> syncTableStatusForOrder(int orderId) async {
    if (await _useBackendApi()) return;

    try {
      final db = await _dbHelper.database;
      final orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (orders.isEmpty) return;

      final order = orders.first;
      final tableId = order['table_id'] as int?;
      if (tableId == null) return;

      final paymentStatus = order['payment_status'] as String? ?? 'Unpaid';
      final orderStatus = order['status'] as String? ?? 'Pending';
      final isPaid = paymentStatus == 'Paid' ||
          orderStatus == 'Completed' ||
          orderStatus == 'Paid';

      if (isPaid) {
        await releaseTableIfPaid(tableId);
      } else if (orderStatus != 'Cancelled') {
        await markTableOccupied(tableId);
      }
    } catch (e) {
      print('Error in syncTableStatusForOrder: $e');
    }
  }

  Future<void> markTableOccupied(int tableId) async {
    try {
      if (await _useBackendApi()) {
        await updateTableStatus(tableId, 'Occupied');
        return;
      }

      final db = await _dbHelper.database;
      await db.update(
        'tables',
        {'status': 'Occupied'},
        where: 'id = ? OR merged_with_id = ?',
        whereArgs: [tableId, tableId],
      );

      SyncService.instance.broadcastEvent(
        'database_update',
        {'tableId': tableId, 'status': 'Occupied'},
      );
    } catch (e) {
      print('Error in markTableOccupied: $e');
    }
  }

  Future<void> releaseTableIfPaid(int tableId) async {
    try {
      // Do not release a Web table without checking backend orders/bookings.
      if (await _useBackendApi()) return;

      final db = await _dbHelper.database;

      final activeOrders = await db.query(
        'orders',
        where:
            'table_id = ? AND payment_status != ? AND status NOT IN (?, ?)',
        whereArgs: [tableId, 'Paid', 'Completed', 'Cancelled'],
      );

      if (activeOrders.isNotEmpty) {
        await markTableOccupied(tableId);
        return;
      }

      final now = DateTime.now();
      final bookings = await db.query(
        'bookings',
        where: 'table_id = ? AND status = ?',
        whereArgs: [tableId, 'Confirmed'],
      );

      final hasCurrentBooking = bookings.any((booking) {
        final value = booking['booking_time'] as String?;
        if (value == null) return false;

        final bookingTime = DateTime.tryParse(value);
        if (bookingTime == null) return false;

        final slotEnd = bookingTime.add(const Duration(hours: 1));
        return !now.isBefore(bookingTime) && now.isBefore(slotEnd);
      });

      if (hasCurrentBooking) {
        await markTableOccupied(tableId);
        return;
      }

      await db.update(
        'tables',
        {'status': 'Available', 'merged_with_id': null},
        where: 'id = ? OR merged_with_id = ?',
        whereArgs: [tableId, tableId],
      );

      SyncService.instance.broadcastEvent(
        'database_update',
        {'tableId': tableId, 'status': 'Available'},
      );
    } catch (e) {
      print('Error in releaseTableIfPaid: $e');
    }
  }

  Future<void> syncAllTableStatuses([int? restaurantId]) async {
    // Web must not access SQLite. Backend-side reconciliation is needed here.
    if (await _useBackendApi()) return;

    try {
      final db = await _dbHelper.database;
      final restId =
          restaurantId ?? DatabaseHelper.currentRestaurantId ?? 1;

      final tables = await db.query(
        'tables',
        where: 'restaurant_id = ? OR restaurant_id IS NULL',
        whereArgs: [restId],
      );

      final now = DateTime.now();

      for (final table in tables) {
        final tableId = table['id'] as int;
        final currentStatus = table['status'] as String? ?? 'Available';

        final activeOrders = await db.query(
          'orders',
          where:
              'table_id = ? AND payment_status != ? AND status NOT IN (?, ?)',
          whereArgs: [tableId, 'Paid', 'Completed', 'Cancelled'],
        );

        final bookings = await db.query(
          'bookings',
          where: 'table_id = ? AND status = ?',
          whereArgs: [tableId, 'Confirmed'],
        );

        final hasCurrentBooking = bookings.any((booking) {
          final value = booking['booking_time'] as String?;
          if (value == null) return false;

          final bookingTime = DateTime.tryParse(value);
          if (bookingTime == null) return false;

          final slotEnd = bookingTime.add(const Duration(hours: 1));
          return !now.isBefore(bookingTime) && now.isBefore(slotEnd);
        });

        if (activeOrders.isNotEmpty || hasCurrentBooking) {
          if (currentStatus != 'Occupied') {
            await db.update(
              'tables',
              {'status': 'Occupied'},
              where: 'id = ?',
              whereArgs: [tableId],
            );
          }
        } else if (currentStatus == 'Occupied' ||
            currentStatus == 'Billing Pending') {
          await db.update(
            'tables',
            {'status': 'Available'},
            where: 'id = ?',
            whereArgs: [tableId],
          );
        }
      }
    } catch (e) {
      print('Error in syncAllTableStatuses: $e');
    }
  }

  List<TableModel> _parseTables(dynamic response) {
    if (response is! List) {
      throw const FormatException(
        'Expected a table list from the backend',
      );
    }

    return response.map((item) {
      if (item is! Map) {
        throw const FormatException('Invalid table item from backend');
      }
      return TableModel.fromMap(Map<String, dynamic>.from(item));
    }).toList();
  }

  Map<String, dynamic> _toApiMap(TableModel table) {
    return {
      'tableNumber': table.tableNumber,
      'name': table.name,
      'capacity': table.capacity,
      'status': table.status,
      'section': table.section,
      'tableType': table.tableType,
      'restaurantId':
          table.restaurantId ?? DatabaseHelper.currentRestaurantId ?? 1,
      'active': table.isActive,
      'reservable': table.isReservable,
      'notes': table.notes,
    };
  }
}
