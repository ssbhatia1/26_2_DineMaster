import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../widgets/food_attributes_badge.dart';
import 'recipe_management_screen.dart';

class ProductsManagementScreen extends StatefulWidget {
  const ProductsManagementScreen({super.key});

  @override
  State<ProductsManagementScreen> createState() => _ProductsManagementScreenState();
}

class _ProductsManagementScreenState extends State<ProductsManagementScreen> {
  List<ProductModel> _products = [];
  bool _isLoading = true;
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
  }

  Future<void> _loadCategories() async {
    final db = await DatabaseHelper.instance.database;
    final cats = await db.query('categories');
    if (!mounted) return;
    setState(() {
      final dbCats = cats.map((c) => c['name'] as String).toList();
      if (dbCats.isEmpty) {
        _categories = ['All', 'Starters', 'Main Course', 'Breads', 'Beverages', 'Desserts'];
      } else {
        _categories = ['All', ...dbCats];
      }
    });
  }

  Future<void> _loadProducts() async {
    final db = await DatabaseHelper.instance.database;
    final whereClause = _selectedCategory == 'All'
        ? 'restaurant_id = ?'
        : 'restaurant_id = ? AND category = ?';
    final whereArgs = _selectedCategory == 'All'
        ? [DatabaseHelper.currentRestaurantId]
        : [DatabaseHelper.currentRestaurantId, _selectedCategory];

    final productMaps = await db.query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    if (!mounted) return;
    setState(() {
      _products = productMaps.map((m) => ProductModel.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  List<ProductModel> get _filteredProducts {
    if (_searchQuery.trim().isEmpty) return _products;
    final q = _searchQuery.toLowerCase();
    return _products.where((p) {
      final nameMatches = p.name.toLowerCase().contains(q);
      final catMatches = p.category.toLowerCase().contains(q);
      final attrMatches = p.attributes.any((a) => a.toLowerCase().contains(q));
      final dietMatches = p.dietaryPreferences.any((d) => d.toLowerCase().contains(q));
      final tasteMatches = p.tastePreferences.any((t) => t.toLowerCase().contains(q));
      return nameMatches || catMatches || attrMatches || dietMatches || tasteMatches;
    }).toList();
  }

  Future<void> _showProductDialog([ProductModel? existingProduct]) async {
    final isEditing = existingProduct != null;
    final db = await DatabaseHelper.instance.database;

    // Load raw ingredients for recipe management
    final ingredients = await db.query('ingredients', orderBy: 'name ASC');

    // Load recipe items if editing
    List<Map<String, dynamic>> localRecipe = [];
    if (isEditing && existingProduct.id != null) {
      final recipeItems = await db.rawQuery('''
        SELECT recipes.*, ingredients.name as ingredient_name, ingredients.unit 
        FROM recipes 
        JOIN ingredients ON recipes.ingredient_id = ingredients.id 
        WHERE recipes.product_id = ?
      ''', [existingProduct.id]);
      localRecipe = recipeItems.map((item) => {
        'ingredient_id': item['ingredient_id'],
        'ingredient_name': item['ingredient_name'],
        'quantity_used': item['quantity_used'],
        'unit': item['unit'],
      }).toList();
    }

    final nameController = TextEditingController(text: existingProduct?.name ?? '');
    final priceController = TextEditingController(text: existingProduct != null ? existingProduct.price.toString() : '');
    final descController = TextEditingController(text: existingProduct?.description ?? '');
    final prepTimeController = TextEditingController(text: (existingProduct?.prepTime ?? 5).toString());
    final cookTimeController = TextEditingController(text: (existingProduct?.cookTime ?? 10).toString());
    final customNotesController = TextEditingController(text: existingProduct?.customDietaryNotes ?? '');
    final ingredientController = TextEditingController();
    final recipeQtyController = TextEditingController();
    final stepController = TextEditingController();
    int? selectedIngredientId;

    final localSteps = existingProduct?.recipeSteps != null && existingProduct!.recipeSteps!.isNotEmpty
        ? existingProduct.recipeSteps!.split('\n').where((s) => s.trim().isNotEmpty).toList()
        : <String>[];

    final ingredientsList = existingProduct?.ingredients != null && existingProduct!.ingredients!.isNotEmpty
        ? existingProduct.ingredients!.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    String category = existingProduct?.category ?? (_categories.length > 1 ? _categories[1] : 'Starters');
    int productType = existingProduct?.isVeg ?? 1; // 1=Veg, 0=Non-Veg, 2=Egg, 3=Jain
    bool isAvailable = existingProduct?.isAvailable ?? true;
    double gstPercentage = existingProduct?.gstPercentage ?? 5.0;

    // Preferences & Attributes Sets
    final Set<String> dietaryPreferences = Set.from(existingProduct?.dietaryPreferences ?? []);
    final Set<String> tastePreferences = Set.from(existingProduct?.tastePreferences ?? []);
    final Set<String> attributes = Set.from(existingProduct?.attributes ?? []);

    final prefs = await SharedPreferences.getInstance();
    final rawScale = prefs.getString('gst_scale') ?? '0.0,5.0,12.0,18.0,28.0';
    List<double> gstSlabs = rawScale
        .split(',')
        .map((s) => double.tryParse(s.trim()) ?? -1.0)
        .where((val) => val >= 0.0)
        .toList();
    if (gstSlabs.isEmpty) gstSlabs = [0.0, 5.0, 12.0, 18.0, 28.0];
    if (!gstSlabs.contains(gstPercentage)) gstSlabs.add(gstPercentage);
    gstSlabs.sort();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => DefaultTabController(
          length: 4,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 720,
              height: 640,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.deepPurple.shade50,
                        child: Icon(
                          isEditing ? Icons.edit_note : Icons.add_business_outlined,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing ? 'Edit Food Item' : 'Add New Food Item',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Text(
                              'Configure item details, dietary & taste preferences, and badges',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Section Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const TabBar(
                      isScrollable: true,
                      labelColor: Colors.deepPurple,
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: Colors.deepPurple,
                      indicatorWeight: 3,
                      tabs: [
                        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Basic Info'),
                        Tab(icon: Icon(Icons.room_service_outlined, size: 18), text: 'Dietary & Taste'),
                        Tab(icon: Icon(Icons.stars_outlined, size: 18), text: 'Food Attributes'),
                        Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Recipe & Ingredients'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Basic Information
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: nameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Product / Dish Name *',
                                        prefixIcon: Icon(Icons.fastfood_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Price (₹) *',
                                        prefixText: '₹ ',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: category,
                                      items: _categories
                                          .where((c) => c != 'All')
                                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                          .toList(),
                                      onChanged: (val) => setDlgState(() => category = val!),
                                      decoration: const InputDecoration(
                                        labelText: 'Category',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<double>(
                                      value: gstPercentage,
                                      items: gstSlabs
                                          .map((rate) => DropdownMenuItem(value: rate, child: Text('$rate % GST')))
                                          .toList(),
                                      onChanged: (val) => setDlgState(() => gstPercentage = val!),
                                      decoration: const InputDecoration(
                                        labelText: 'GST Tax Rate',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: descController,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Food Description (Visible to customers)',
                                  hintText: 'Brief description of ingredients, style, or preparation...',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: prepTimeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Prep Time (Mins)',
                                        prefixIcon: Icon(Icons.timer_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: cookTimeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Cook Time (Mins)',
                                        prefixIcon: Icon(Icons.outdoor_grill_outlined),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text('Food Classification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 6),
                              ToggleButtons(
                                isSelected: [productType == 1, productType == 0, productType == 2, productType == 3],
                                onPressed: (index) {
                                  setDlgState(() {
                                    if (index == 0) productType = 1; // Veg
                                    if (index == 1) productType = 0; // Non-Veg
                                    if (index == 2) productType = 2; // Egg
                                    if (index == 3) {
                                      productType = 3; // Jain
                                      dietaryPreferences.add('Pure Jain');
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                selectedColor: Colors.white,
                                fillColor: productType == 1
                                    ? Colors.green
                                    : (productType == 0
                                        ? Colors.red
                                        : (productType == 2 ? Colors.orange : Colors.teal)),
                                children: const [
                                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Icon(Icons.eco, size: 16), SizedBox(width: 4), Text('Veg')])),
                                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Icon(Icons.restaurant, size: 16), SizedBox(width: 4), Text('Non-Veg')])),
                                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Icon(Icons.egg, size: 16), SizedBox(width: 4), Text('Egg')])),
                                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Icon(Icons.spa, size: 16), SizedBox(width: 4), Text('Jain')])),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('Available for Ordering', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(isAvailable ? 'In stock and active on POS & Menu' : 'Marked Out of Stock'),
                                value: isAvailable,
                                onChanged: (val) => setDlgState(() => isAvailable = val),
                                activeColor: Colors.deepPurple,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),

                        // Tab 2: Dietary & Taste Preferences (Item-level Show/Hide Controls)
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.tune, color: Colors.blue, size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Show/Hide Controls: Enable ONLY the preferences applicable to this specific food item. Customers/waiters will only be shown enabled options.',
                                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Dietary Preferences
                              const Text('Dietary Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              _buildPreferenceToggleCard(
                                title: 'Pure Jain',
                                description: 'Made strictly with no root vegetables (potato, onion, garlic).',
                                icon: Icons.spa,
                                iconColor: Colors.green,
                                isEnabled: dietaryPreferences.contains('Pure Jain'),
                                onToggle: (enabled) {
                                  setDlgState(() {
                                    if (enabled) {
                                      dietaryPreferences.add('Pure Jain');
                                    } else {
                                      dietaryPreferences.remove('Pure Jain');
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              _buildPreferenceToggleCard(
                                title: 'Semi Jain',
                                description: 'Prepared with partial Jain considerations as per guest request.',
                                icon: Icons.eco,
                                iconColor: Colors.teal,
                                isEnabled: dietaryPreferences.contains('Semi Jain'),
                                onToggle: (enabled) {
                                  setDlgState(() {
                                    if (enabled) {
                                      dietaryPreferences.add('Semi Jain');
                                    } else {
                                      dietaryPreferences.remove('Semi Jain');
                                    }
                                  });
                                },
                              ),
                              const Divider(height: 28),

                              // Taste Preferences
                              const Text('Taste Profile Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              _buildPreferenceToggleCard(
                                title: 'Sweet',
                                description: 'Sweet taste profile or customizable sweetness level.',
                                icon: Icons.cake_outlined,
                                iconColor: Colors.pink,
                                isEnabled: tastePreferences.contains('Sweet'),
                                onToggle: (enabled) {
                                  setDlgState(() {
                                    if (enabled) {
                                      tastePreferences.add('Sweet');
                                    } else {
                                      tastePreferences.remove('Sweet');
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              _buildPreferenceToggleCard(
                                title: 'Spicy',
                                description: 'Offers spicy flavor seasoning or spice adjustment.',
                                icon: Icons.whatshot,
                                iconColor: Colors.deepOrange,
                                isEnabled: tastePreferences.contains('Spicy'),
                                onToggle: (enabled) {
                                  setDlgState(() {
                                    if (enabled) {
                                      tastePreferences.add('Spicy');
                                    } else {
                                      tastePreferences.remove('Spicy');
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              _buildPreferenceToggleCard(
                                title: 'Extra Spicy',
                                description: 'Allows request for extreme/extra spicy preparation.',
                                icon: Icons.local_fire_department,
                                iconColor: Colors.red,
                                isEnabled: tastePreferences.contains('Extra Spicy'),
                                onToggle: (enabled) {
                                  setDlgState(() {
                                    if (enabled) {
                                      tastePreferences.add('Extra Spicy');
                                    } else {
                                      tastePreferences.remove('Extra Spicy');
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        // Tab 3: Food Attributes & Badges (Item-level Show/Hide Controls)
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Highlight Badges & Marketing Tags',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Text(
                                'Select badges to display on POS, waiter screens, and digital menus.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildAttributeFilterChip(
                                    label: "Chef's Special",
                                    icon: Icons.star_rounded,
                                    color: Colors.amber.shade800,
                                    isSelected: attributes.contains("Chef's Special"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Chef's Special") : attributes.remove("Chef's Special")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Bestseller",
                                    icon: Icons.trending_up,
                                    color: Colors.deepOrange,
                                    isSelected: attributes.contains("Bestseller"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Bestseller") : attributes.remove("Bestseller")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Recommended",
                                    icon: Icons.thumb_up_alt_outlined,
                                    color: Colors.deepPurple,
                                    isSelected: attributes.contains("Recommended"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Recommended") : attributes.remove("Recommended")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "New",
                                    icon: Icons.auto_awesome,
                                    color: Colors.cyan.shade700,
                                    isSelected: attributes.contains("New"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("New") : attributes.remove("New")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Popular",
                                    icon: Icons.favorite,
                                    color: Colors.pink,
                                    isSelected: attributes.contains("Popular"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Popular") : attributes.remove("Popular")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Healthy",
                                    icon: Icons.health_and_safety_outlined,
                                    color: Colors.green,
                                    isSelected: attributes.contains("Healthy"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Healthy") : attributes.remove("Healthy")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Vegan",
                                    icon: Icons.grass,
                                    color: Colors.green.shade800,
                                    isSelected: attributes.contains("Vegan"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Vegan") : attributes.remove("Vegan")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Gluten-Free",
                                    icon: Icons.grain,
                                    color: Colors.brown,
                                    isSelected: attributes.contains("Gluten-Free"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Gluten-Free") : attributes.remove("Gluten-Free")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Contains Dairy",
                                    icon: Icons.water_drop_outlined,
                                    color: Colors.blue,
                                    isSelected: attributes.contains("Contains Dairy"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Contains Dairy") : attributes.remove("Contains Dairy")),
                                  ),
                                  _buildAttributeFilterChip(
                                    label: "Contains Nuts",
                                    icon: Icons.cookie_outlined,
                                    color: Colors.brown.shade700,
                                    isSelected: attributes.contains("Contains Nuts"),
                                    onChanged: (sel) => setDlgState(() => sel ? attributes.add("Contains Nuts") : attributes.remove("Contains Nuts")),
                                  ),
                                ],
                              ),
                              const Divider(height: 32),
                              const Text('Custom Dietary / Allergy Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: customNotesController,
                                decoration: const InputDecoration(
                                  labelText: 'Custom Notes (e.g. "Low Sodium", "Nut-Free recipe")',
                                  hintText: 'Add specific notes visible to customer/staff...',
                                  prefixIcon: Icon(Icons.notes),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Tab 4: Recipe Ingredients & Steps
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Linked Inventory Ingredients', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  TextButton.icon(
                                    icon: const Icon(Icons.settings, size: 16),
                                    label: const Text('Manage Stock Ingredients', style: TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showIngredientsManager();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<int>(
                                      value: selectedIngredientId,
                                      hint: const Text('Select Raw Material'),
                                      isExpanded: true,
                                      items: ingredients.map((ing) {
                                        return DropdownMenuItem<int>(
                                          value: ing['id'] as int,
                                          child: Text('${ing['name']} (${ing['unit']})'),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setDlgState(() => selectedIngredientId = val),
                                      decoration: const InputDecoration(
                                        labelText: 'Ingredient',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: recipeQtyController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Qty Used',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.deepPurple, size: 32),
                                    onPressed: () {
                                      final qty = double.tryParse(recipeQtyController.text.trim()) ?? 0.0;
                                      if (selectedIngredientId != null && qty > 0) {
                                        final matched = ingredients.firstWhere((i) => i['id'] == selectedIngredientId);
                                        setDlgState(() {
                                          localRecipe.add({
                                            'ingredient_id': selectedIngredientId,
                                            'ingredient_name': matched['name'],
                                            'quantity_used': qty,
                                            'unit': matched['unit'],
                                          });
                                          selectedIngredientId = null;
                                          recipeQtyController.clear();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (localRecipe.isNotEmpty)
                                ...localRecipe.asMap().entries.map((entry) {
                                  final rItem = entry.value;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    child: ListTile(
                                      dense: true,
                                      title: Text(rItem['ingredient_name']),
                                      subtitle: Text('${rItem['quantity_used']} ${rItem['unit']} per serving'),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                        onPressed: () => setDlgState(() => localRecipe.removeAt(entry.key)),
                                      ),
                                    ),
                                  );
                                }),
                              const Divider(height: 24),
                              const Text('Step-by-Step Cooking Instructions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: stepController,
                                      decoration: const InputDecoration(
                                        labelText: 'Enter instruction step',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.deepPurple, size: 32),
                                    onPressed: () {
                                      final val = stepController.text.trim();
                                      if (val.isNotEmpty) {
                                        setDlgState(() {
                                          localSteps.add(val);
                                          stepController.clear();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (localSteps.isEmpty)
                                const Text('No cooking steps defined.', style: TextStyle(color: Colors.grey, fontSize: 12))
                              else
                                ...localSteps.asMap().entries.map((entry) {
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.deepPurple.shade50,
                                      child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 10, color: Colors.deepPurple)),
                                    ),
                                    title: Text(entry.value),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                      onPressed: () => setDlgState(() => localSteps.removeAt(entry.key)),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.save, size: 18),
                        label: Text(isEditing ? 'Save Changes' : 'Add Food Item'),
                        onPressed: () async {
                          final name = nameController.text.trim();
                          final price = double.tryParse(priceController.text.trim()) ?? 0.0;
                          final desc = descController.text.trim();

                          if (name.isEmpty || price <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter valid dish name and price')),
                            );
                            return;
                          }

                          final allIngredientsList = {...ingredientsList};
                          for (var rItem in localRecipe) {
                            allIngredientsList.add(rItem['ingredient_name'] as String);
                          }

                          final data = {
                            'name': name,
                            'price': price,
                            'description': desc,
                            'ingredients': allIngredientsList.join(','),
                            'category': category,
                            'is_veg': productType,
                            'is_available': isAvailable ? 1 : 0,
                            'restaurant_id': DatabaseHelper.currentRestaurantId,
                            'recipe_steps': localSteps.join('\n'),
                            'prep_time': int.tryParse(prepTimeController.text.trim()) ?? 5,
                            'cook_time': int.tryParse(cookTimeController.text.trim()) ?? 10,
                            'gst_percentage': gstPercentage,
                            'dietary_preferences': jsonEncode(dietaryPreferences.toList()),
                            'taste_preferences': jsonEncode(tastePreferences.toList()),
                            'attributes': jsonEncode(attributes.toList()),
                            'custom_dietary_notes': customNotesController.text.trim(),
                          };

                          int productId;
                          if (isEditing && existingProduct.id != null) {
                            productId = existingProduct.id!;
                            await db.update('products', data, where: 'id = ?', whereArgs: [productId]);
                          } else {
                            productId = await db.insert('products', data);
                          }

                          // Sync recipe ingredients table
                          await db.delete('recipes', where: 'product_id = ?', whereArgs: [productId]);
                          for (var rItem in localRecipe) {
                            await db.insert('recipes', {
                              'product_id': productId,
                              'ingredient_id': rItem['ingredient_id'],
                              'quantity_used': rItem['quantity_used'],
                            });
                          }

                          Navigator.pop(context);
                          _loadProducts();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Product "$name" saved successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreferenceToggleCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? iconColor.withAlpha(20) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnabled ? iconColor : Colors.grey.shade300,
          width: isEnabled ? 1.5 : 1,
        ),
      ),
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: iconColor.withAlpha(35),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        value: isEnabled,
        onChanged: onToggle,
        activeColor: iconColor,
      ),
    );
  }

  Widget _buildAttributeFilterChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selectedColor: color,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(color: isSelected ? color : Colors.grey.shade300),
      onSelected: onChanged,
    );
  }

  void _showIngredientsManager() {
    final nameController = TextEditingController();
    final unitController = TextEditingController();
    List<Map<String, dynamic>> ingredients = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setIngState) {
          void loadIngs() async {
            final db = await DatabaseHelper.instance.database;
            final res = await db.query('ingredients', orderBy: 'name ASC');
            setIngState(() => ingredients = res);
          }

          if (ingredients.isEmpty) loadIngs();

          return AlertDialog(
            title: const Text('Manage Stock Ingredients'),
            content: SizedBox(
              width: 450,
              height: 400,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Ingredient Name (e.g. Cheese)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'Unit (kg, g, L)'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.deepPurple),
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isNotEmpty) {
                            final db = await DatabaseHelper.instance.database;
                            await db.insert('ingredients', {
                              'name': name,
                              'unit': unitController.text.trim(),
                              'stock_quantity': 0.0,
                              'restaurant_id': DatabaseHelper.currentRestaurantId,
                            });
                            nameController.clear();
                            unitController.clear();
                            loadIngs();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: ingredients.length,
                      itemBuilder: (context, index) {
                        final ing = ingredients[index];
                        return ListTile(
                          title: Text(ing['name'] as String),
                          subtitle: Text('Unit: ${ing['unit']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              final db = await DatabaseHelper.instance.database;
                              await db.delete('ingredients', where: 'id = ?', whereArgs: [ing['id']]);
                              loadIngs();
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCategoryManager() {
    final catController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setCatState) => AlertDialog(
          title: const Text('Manage Categories'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: catController,
                        decoration: const InputDecoration(labelText: 'New Category Name'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.deepPurple),
                      onPressed: () async {
                        final name = catController.text.trim();
                        if (name.isNotEmpty) {
                          final db = await DatabaseHelper.instance.database;
                          try {
                            await db.insert('categories', {
                              'name': name,
                              'restaurant_id': DatabaseHelper.currentRestaurantId,
                            });
                            catController.clear();
                            _loadCategories();
                            Navigator.pop(context);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Category already exists')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(int? id, String name) {
    if (id == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete product "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete('products', where: 'id = ?', whereArgs: [id]);
              Navigator.pop(context);
              _loadProducts();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Products & Preferences'),
        actions: [
          DropdownButton<String>(
            value: _selectedCategory,
            underline: const SizedBox(),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _selectedCategory = val;
                _isLoading = true;
              });
              _loadProducts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            onPressed: _showCategoryManager,
            tooltip: 'Manage Categories',
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: _showIngredientsManager,
            tooltip: 'Manage Stock Ingredients',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search and Summary Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search food item by name, category, or attribute...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${filtered.length} Items',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Product List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fastfood_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty ? 'No products match your search' : 'No products found',
                              style: const TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: product.isVeg == 1
                                            ? Colors.green.withAlpha(25)
                                            : (product.isVeg == 2
                                                ? Colors.yellow.withAlpha(50)
                                                : (product.isVeg == 3
                                                    ? Colors.teal.withAlpha(25)
                                                    : Colors.red.withAlpha(25))),
                                        child: Icon(
                                          product.isVeg == 1
                                              ? Icons.eco
                                              : (product.isVeg == 2
                                                  ? Icons.egg
                                                  : (product.isVeg == 3
                                                      ? Icons.spa
                                                      : Icons.restaurant)),
                                          color: product.isVeg == 1
                                              ? Colors.green
                                              : (product.isVeg == 2
                                                  ? Colors.orange
                                                  : (product.isVeg == 3
                                                      ? Colors.teal
                                                      : Colors.red)),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    product.name,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '₹${product.price.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.deepPurple,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${product.category} • GST: ${product.gstPercentage}% • ${product.isAvailable ? "In Stock" : "Out of Stock"}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            if (product.description != null && product.description!.trim().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                product.description!,
                                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.menu_book, color: Colors.orange, size: 20),
                                            onPressed: () async {
                                              final result = await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => RecipeManagementScreen(product: product.toMap()),
                                                ),
                                              );
                                              if (result == true) _loadProducts();
                                            },
                                            tooltip: 'Manage Recipe',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                                            onPressed: () => _showProductDialog(product),
                                            tooltip: 'Edit Food Item & Preferences',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            onPressed: () => _confirmDelete(product.id, product.name),
                                            tooltip: 'Delete Product',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  // Attributes & Preferences Badges Row
                                  if (product.dietaryPreferences.isNotEmpty ||
                                      product.tastePreferences.isNotEmpty ||
                                      product.attributes.isNotEmpty ||
                                      (product.customDietaryNotes != null && product.customDietaryNotes!.isNotEmpty)) ...[
                                    const SizedBox(height: 8),
                                    FoodAttributesBadge(product: product, compact: false),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Food Item'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }
}
