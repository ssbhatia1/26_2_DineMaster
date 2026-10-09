import '../core/database/database_helper.dart';
import '../models/table_model.dart';
import '../services/sync_service.dart';

class TableRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<TableModel>> getTables() async {
    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, u.name as waiter_name 
      FROM tables t
      LEFT JOIN users u ON t.waiter_id = u.id
      WHERE (t.restaurant_id = ? OR t.restaurant_id IS NULL)
      ORDER BY t.table_number ASC
    ''', [restaurantId]);
    return List.generate(maps.length, (i) => TableModel.fromMap(maps[i]));
  }

  Future<int> addTable(TableModel table) async {
    final db = await _dbHelper.database;
    final map = table.toMap();
    map.remove('waiter_name');
    if (map['id'] == null) {
      map.remove('id');
    }
    map['restaurant_id'] = DatabaseHelper.currentRestaurantId ?? 1;
    final id = await db.insert('tables', map);
    SyncService.instance.broadcastEvent('database_update', {'action': 'add_table', 'tableId': id});
    return id;
  }

  Future<int> updateTable(TableModel table) async {
    final db = await _dbHelper.database;
    final map = table.toMap();
    map.remove('waiter_name');
    map['restaurant_id'] = DatabaseHelper.currentRestaurantId ?? 1;
    final count = await db.update(
      'tables',
      map,
      where: 'id = ?',
      whereArgs: [table.id],
    );
    SyncService.instance.broadcastEvent('database_update', {'action': 'update_table', 'tableId': table.id});
    return count;
  }

  Future<int> deleteTable(int id) async {
    final db = await _dbHelper.database;
    final count = await db.delete(
      'tables',
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.broadcastEvent('database_update', {'action': 'delete_table', 'tableId': id});
    return count;
  }

  Future<int> updateTableStatus(int id, String status) async {
    final db = await _dbHelper.database;
    final count = await db.update(
      'tables',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.broadcastEvent('database_update', {'action': 'update_status', 'tableId': id, 'status': status});
    return count;
  }

  /// Keep table occupied while order is active, or release to Available when fully paid.
  Future<void> syncTableStatusForOrder(int orderId) async {
    try {
      final db = await _dbHelper.database;
      final orderList = await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (orderList.isEmpty) return;

      final order = orderList.first;
      final tableId = order['table_id'] as int?;
      if (tableId == null) return;

      final paymentStatus = order['payment_status'] as String? ?? 'Unpaid';
      final orderStatus = order['status'] as String? ?? 'Pending';
      final isPaid = paymentStatus == 'Paid' || orderStatus == 'Completed' || orderStatus == 'Paid';

      if (isPaid) {
        // Order is paid, release table if no other unpaid active orders or current booking
        await releaseTableIfPaid(tableId);
      } else if (orderStatus != 'Cancelled') {
        // Order is active & unpaid -> keep table status as Occupied
        await markTableOccupied(tableId);
      }
    } catch (e) {
      print('Error in syncTableStatusForOrder: $e');
    }
  }

  /// Mark table (and any merged member tables) as Occupied while active
  Future<void> markTableOccupied(int tableId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'tables',
        {'status': 'Occupied'},
        where: 'id = ? OR merged_with_id = ?',
        whereArgs: [tableId, tableId],
      );
      SyncService.instance.broadcastEvent('database_update', {'tableId': tableId, 'status': 'Occupied'});
    } catch (e) {
      print('Error in markTableOccupied: $e');
    }
  }

  /// Automatically release table to Available once bill is fully paid,
  /// provided no other active unpaid orders or active reservations exist.
  Future<void> releaseTableIfPaid(int tableId) async {
    try {
      final db = await _dbHelper.database;

      // Check for any remaining active unpaid orders on this table
      final activeUnpaidOrders = await db.query(
        'orders',
        where: 'table_id = ? AND payment_status != ? AND status NOT IN (?, ?)',
        whereArgs: [tableId, 'Paid', 'Completed', 'Cancelled'],
      );

      if (activeUnpaidOrders.isNotEmpty) {
        // Still has active unpaid orders, keep Occupied
        await markTableOccupied(tableId);
        return;
      }

      // Check for active current booking slot
      final now = DateTime.now();
      final bookings = await db.query(
        'bookings',
        where: 'table_id = ? AND status = ?',
        whereArgs: [tableId, 'Confirmed'],
      );

      bool hasCurrentBooking = false;
      for (final b in bookings) {
        final bTimeStr = b['booking_time'] as String?;
        if (bTimeStr == null) continue;
        final bTime = DateTime.tryParse(bTimeStr);
        if (bTime == null) continue;
        final slotEnd = bTime.add(const Duration(hours: 1));
        if (!now.isBefore(bTime) && now.isBefore(slotEnd)) {
          hasCurrentBooking = true;
          break;
        }
      }

      if (hasCurrentBooking) {
        await markTableOccupied(tableId);
        return;
      }

      // No active unpaid orders and no current booking -> Set to Available & unmerge
      await db.update(
        'tables',
        {'status': 'Available', 'merged_with_id': null},
        where: 'id = ? OR merged_with_id = ?',
        whereArgs: [tableId, tableId],
      );

      SyncService.instance.broadcastEvent('database_update', {'tableId': tableId, 'status': 'Available'});
    } catch (e) {
      print('Error in releaseTableIfPaid: $e');
    }
  }

  /// Sanitize and harmonize all table statuses across the database
  Future<void> syncAllTableStatuses([int? restaurantId]) async {
    try {
      final db = await _dbHelper.database;
      final restId = restaurantId ?? DatabaseHelper.currentRestaurantId ?? 1;

      final tables = await db.query(
        'tables',
        where: 'restaurant_id = ? OR restaurant_id IS NULL',
        whereArgs: [restId],
      );

      final now = DateTime.now();

      for (final t in tables) {
        final tableId = t['id'] as int;
        final currentStatus = t['status'] as String? ?? 'Available';

        // Check active unpaid orders
        final activeOrders = await db.query(
          'orders',
          where: 'table_id = ? AND payment_status != ? AND status NOT IN (?, ?)',
          whereArgs: [tableId, 'Paid', 'Completed', 'Cancelled'],
        );

        // Check active bookings
        final bookings = await db.query(
          'bookings',
          where: 'table_id = ? AND status = ?',
          whereArgs: [tableId, 'Confirmed'],
        );

        bool hasCurrentBooking = false;
        for (final b in bookings) {
          final bTimeStr = b['booking_time'] as String?;
          if (bTimeStr == null) continue;
          final bTime = DateTime.tryParse(bTimeStr);
          if (bTime == null) continue;
          final slotEnd = bTime.add(const Duration(hours: 1));
          if (!now.isBefore(bTime) && now.isBefore(slotEnd)) {
            hasCurrentBooking = true;
            break;
          }
        }

        if (activeOrders.isNotEmpty || hasCurrentBooking) {
          if (currentStatus != 'Occupied') {
            await db.update('tables', {'status': 'Occupied'}, where: 'id = ?', whereArgs: [tableId]);
          }
        } else {
          // If no active order and no booking, occupied or billing pending should revert to Available
          if (currentStatus == 'Occupied' || currentStatus == 'Billing Pending') {
            await db.update('tables', {'status': 'Available'}, where: 'id = ?', whereArgs: [tableId]);
          }
        }
      }
    } catch (e) {
      print('Error in syncAllTableStatuses: $e');
    }
  }
}
