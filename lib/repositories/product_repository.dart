import '../core/database/database_helper.dart';
import '../models/product_model.dart';

class ProductRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<ProductModel>> getProducts() async {
    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
    return List.generate(maps.length, (i) => ProductModel.fromMap(maps[i]));
  }

  Future<List<ProductModel>> getProductsByCategory(String category) async {
    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'category = ? AND restaurant_id = ?',
      whereArgs: [category, restaurantId],
    );
    return List.generate(maps.length, (i) => ProductModel.fromMap(maps[i]));
  }

  Future<int> addProduct(ProductModel product) async {
    final db = await _dbHelper.database;
    final map = product.toMap();
    map['restaurant_id'] = DatabaseHelper.currentRestaurantId;
    return await db.insert('products', map);
  }

  Future<int> updateProduct(ProductModel product) async {
    final db = await _dbHelper.database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
