import 'dart:convert';

class ProductModel {
  final int? id;
  final String name;
  final String? description;
  final String? ingredients;
  final double price;
  final String category;
  final int isVeg; // 1=Veg, 0=Non-Veg, 2=Egg, 3=Jain
  final String? imagePath;
  final bool isAvailable;
  final String? recipeSteps;
  final int? prepTime;
  final int? cookTime;
  final int? servings;
  final String? difficulty;
  final String? videoPath;
  final double gstPercentage;

  // Individual Food-Level Preferences & Attributes
  final List<String> dietaryPreferences; // e.g. ['Pure Jain', 'Semi Jain']
  final List<String> tastePreferences;   // e.g. ['Sweet', 'Spicy', 'Extra Spicy']
  final List<String> attributes;         // e.g. ["Chef's Special", "Bestseller", "Recommended", "New", "Popular", "Healthy", "Vegan", "Gluten-Free", "Contains Dairy", "Contains Nuts"]
  final String? customDietaryNotes;

  ProductModel({
    this.id,
    required this.name,
    this.description,
    this.ingredients,
    required this.price,
    required this.category,
    required this.isVeg,
    this.imagePath,
    this.isAvailable = true,
    this.recipeSteps,
    this.prepTime,
    this.cookTime,
    this.servings,
    this.difficulty,
    this.videoPath,
    this.gstPercentage = 5.0,
    this.dietaryPreferences = const [],
    this.tastePreferences = const [],
    this.attributes = const [],
    this.customDietaryNotes,
  });

  // Convenience helper getters
  bool get isPureJain => dietaryPreferences.contains('Pure Jain');
  bool get isSemiJain => dietaryPreferences.contains('Semi Jain');
  bool get isBestseller => attributes.contains('Bestseller');
  bool get isChefsSpecial => attributes.contains("Chef's Special");
  bool get isRecommended => attributes.contains('Recommended');
  bool get isNewItem => attributes.contains('New');
  bool get isPopular => attributes.contains('Popular');
  bool get isHealthy => attributes.contains('Healthy');
  bool get isVegan => attributes.contains('Vegan');
  bool get isGlutenFree => attributes.contains('Gluten-Free');
  bool get hasPreferences => dietaryPreferences.isNotEmpty || tastePreferences.isNotEmpty;
  bool get hasAttributes => attributes.isNotEmpty || (customDietaryNotes != null && customDietaryNotes!.trim().isNotEmpty);

  ProductModel copyWith({
    int? id,
    String? name,
    String? description,
    String? ingredients,
    double? price,
    String? category,
    int? isVeg,
    String? imagePath,
    bool? isAvailable,
    String? recipeSteps,
    int? prepTime,
    int? cookTime,
    int? servings,
    String? difficulty,
    String? videoPath,
    double? gstPercentage,
    List<String>? dietaryPreferences,
    List<String>? tastePreferences,
    List<String>? attributes,
    String? customDietaryNotes,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ingredients: ingredients ?? this.ingredients,
      price: price ?? this.price,
      category: category ?? this.category,
      isVeg: isVeg ?? this.isVeg,
      imagePath: imagePath ?? this.imagePath,
      isAvailable: isAvailable ?? this.isAvailable,
      recipeSteps: recipeSteps ?? this.recipeSteps,
      prepTime: prepTime ?? this.prepTime,
      cookTime: cookTime ?? this.cookTime,
      servings: servings ?? this.servings,
      difficulty: difficulty ?? this.difficulty,
      videoPath: videoPath ?? this.videoPath,
      gstPercentage: gstPercentage ?? this.gstPercentage,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      tastePreferences: tastePreferences ?? this.tastePreferences,
      attributes: attributes ?? this.attributes,
      customDietaryNotes: customDietaryNotes ?? this.customDietaryNotes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ingredients': ingredients,
      'price': price,
      'category': category,
      'is_veg': isVeg,
      'image_path': imagePath,
      'is_available': isAvailable ? 1 : 0,
      'recipe_steps': recipeSteps,
      'prep_time': prepTime,
      'cook_time': cookTime,
      'servings': servings,
      'difficulty': difficulty,
      'video_path': videoPath,
      'gst_percentage': gstPercentage,
      'dietary_preferences': jsonEncode(dietaryPreferences),
      'taste_preferences': jsonEncode(tastePreferences),
      'attributes': jsonEncode(attributes),
      'custom_dietary_notes': customDietaryNotes,
    };
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    return [];
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      name: map['name'] ?? '',
      description: map['description'],
      ingredients: map['ingredients'],
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'General',
      isVeg: map['is_veg'] ?? 1,
      imagePath: map['image_path'],
      isAvailable: map['is_available'] == 1 || map['is_available'] == true,
      recipeSteps: map['recipe_steps'],
      prepTime: map['prep_time'],
      cookTime: map['cook_time'],
      servings: map['servings'],
      difficulty: map['difficulty'],
      videoPath: map['video_path'],
      gstPercentage: (map['gst_percentage'] as num?)?.toDouble() ?? 5.0,
      dietaryPreferences: _parseStringList(map['dietary_preferences']),
      tastePreferences: _parseStringList(map['taste_preferences']),
      attributes: _parseStringList(map['attributes']),
      customDietaryNotes: map['custom_dietary_notes'],
    );
  }
}
