import '../core/api/api_mode.dart';
import '../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../services/backend_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final BackendApiClient _apiClient = const BackendApiClient();

  Future<List<ProductModel>> getProducts() async {
    if (await _useBackendApi()) {
      final restaurantId = DatabaseHelper.currentRestaurantId;
      final response = await _apiClient.getJson(
        '/api/products?restaurantId=$restaurantId',
      );
      return _parseProducts(response);
    }

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
    if (await _useBackendApi()) {
      final response = await _apiClient.getJson(
        '/api/products/category/${Uri.encodeComponent(category)}'
        '?restaurantId=${DatabaseHelper.currentRestaurantId}',
      );
      return _parseProducts(response);
    }

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
    if (await _useBackendApi()) {
      final response = await _apiClient.postJson('/api/products', _toApiMap(product));
      return (response['id'] as num).toInt();
    }

    final db = await _dbHelper.database;
    final map = product.toMap();
    map['restaurant_id'] = DatabaseHelper.currentRestaurantId;
    return await db.insert('products', map);
  }

  Future<int> updateProduct(ProductModel product) async {
    if (await _useBackendApi()) {
      final id = product.id;
      if (id == null) throw ArgumentError('Product ID is required for update');
      await _apiClient.putJson('/api/products/$id', _toApiMap(product));
      return 1;
    }

    final db = await _dbHelper.database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    if (await _useBackendApi()) {
      await _apiClient.delete('/api/products/$id');
      return 1;
    }

    final db = await _dbHelper.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> _useBackendApi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('use_backend_api') ?? ApiMode.defaultUseBackendApi;
  }

  List<ProductModel> _parseProducts(dynamic response) {
    if (response is! List) {
      throw const FormatException('Expected a product list from the backend');
    }
    return response
        .map(
          (item) =>
              ProductModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Map<String, dynamic> _toApiMap(ProductModel product) {
    return {
      'name': product.name,
      'description': product.description,
      'ingredients': product.ingredients,
      'price': product.price,
      'category': product.category,
      'is_veg': product.isVeg,
      'imagePath': product.imagePath,
      'is_available': product.isAvailable,
      'recipeSteps': product.recipeSteps,
      'prepTime': product.prepTime,
      'cookTime': product.cookTime,
      'servings': product.servings,
      'difficulty': product.difficulty,
      'videoPath': product.videoPath,
      'gstPercentage': product.gstPercentage,
      'dietaryPreferences': product.dietaryPreferences.join(','),
      'tastePreferences': product.tastePreferences.join(','),
      'attributes': product.attributes.join(','),
      'customDietaryNotes': product.customDietaryNotes,
    };
  }
}
