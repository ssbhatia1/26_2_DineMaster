import '../core/database/database_helper.dart';
import '../models/table_model.dart';

class TableRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<TableModel>> getTables() async {
    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId;
    final List<Map<String, dynamic>> maps = await db.query(
      'tables',
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
    return List.generate(maps.length, (i) => TableModel.fromMap(maps[i]));
  }

  Future<int> addTable(TableModel table) async {
    final db = await _dbHelper.database;
    final map = table.toMap();
    map['restaurant_id'] = DatabaseHelper.currentRestaurantId;
    return await db.insert('tables', map);
  }

  Future<int> updateTable(TableModel table) async {
    final db = await _dbHelper.database;
    return await db.update(
      'tables',
      table.toMap(),
      where: 'id = ?',
      whereArgs: [table.id],
    );
  }

  Future<int> deleteTable(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'tables',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateTableStatus(int id, String status) async {
    final db = await _dbHelper.database;
    return await db.update(
      'tables',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
