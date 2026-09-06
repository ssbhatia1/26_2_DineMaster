import 'package:flutter/material.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import '../repositories/product_repository.dart';
import '../models/product_model.dart';
import '../widgets/food_attributes_badge.dart';

class MenuCardScreen extends StatefulWidget {
  const MenuCardScreen({super.key});

  @override
  State<MenuCardScreen> createState() => _MenuCardScreenState();
}

class _MenuCardScreenState extends State<MenuCardScreen> {
  final ProductRepository _productRepository = ProductRepository();
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final products = await _productRepository.getProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _isLoading = false;
    });
  }

  List<String> get _categories {
    final set = {'All'};
    for (var p in _products) {
      if (p.category.isNotEmpty) set.add(p.category);
    }
    return set.toList();
  }

  List<ProductModel> get _filteredProducts {
    return _products.where((p) {
      final matchesCategory = _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch = _searchQuery.trim().isEmpty ||
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.attributes.any((a) => a.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          p.dietaryPreferences.any((d) => d.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesCategory && matchesSearch;
    }).toList();
  }

  IconData _vegIcon(int isVeg) {
    switch (isVeg) {
      case 1:
        return Icons.eco;
      case 2:
        return Icons.egg;
      case 3:
        return Icons.spa;
      default:
        return Icons.restaurant;
    }
  }

  Color _vegColor(int isVeg) {
    switch (isVeg) {
      case 1:
        return const Color(0xFF2E7D32);
      case 2:
        return const Color(0xFFE65100);
      case 3:
        return const Color(0xFF00897B);
      default:
        return const Color(0xFFC62828);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Menu Card'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(filtered.length),
          _buildCategoryBar(),
          _buildLegend(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : filtered.isEmpty
                    ? const Center(child: Text('No products found matching your filter'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _buildProductCard(filtered[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int itemCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF0E2A54)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(60),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.secondary, width: 1.2),
            ),
            child: const Icon(Icons.menu_book_rounded, color: AppColors.secondary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CULINARY SELECTIONS',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Dine Master Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Browse our curated dishes',
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(35)),
            ),
            child: Column(
              children: [
                Text(
                  '$itemCount',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Dishes',
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search dishes...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final c = _categories[index];
                final selected = c == _selectedCategory;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedCategory = c),
                  selectedColor: AppColors.secondary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: selected ? AppColors.secondary : Colors.grey.shade300),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _legendDot(color: const Color(0xFF2E7D32), icon: Icons.eco, label: 'Veg'),
          const SizedBox(width: 14),
          _legendDot(color: const Color(0xFFC62828), icon: Icons.restaurant, label: 'Non-Veg'),
          const SizedBox(width: 14),
          _legendDot(color: const Color(0xFFE65100), icon: Icons.egg, label: 'Egg'),
          const SizedBox(width: 14),
          _legendDot(color: const Color(0xFF00897B), icon: Icons.spa, label: 'Jain'),
          const Spacer(),
          Text(
            'Prices incl. taxes',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _legendDot({required Color color, required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildProductCard(ProductModel product) {
    final vegColor = _vegColor(product.isVeg);
    final hasTiming = (product.prepTime ?? 0) > 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image / brand area
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withAlpha(235),
                        const Color(0xFF10274D),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: Icon(_vegIcon(product.isVeg), size: 28, color: vegColor),
                    ),
                  ),
                ),
                // Classic veg / non-veg indicator
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 18,
                    height: 18,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: vegColor, width: 1.6),
                    ),
                    child: product.isVeg == 0
                        ? Icon(Icons.change_history, size: 10, color: vegColor)
                        : (product.isVeg == 2
                            ? Icon(Icons.egg, size: 10, color: vegColor)
                            : Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: vegColor, shape: BoxShape.circle),
                                ),
                              )),
                  ),
                ),
                // Availability chip
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: product.isAvailable ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          product.isAvailable ? Icons.check_circle_outline : Icons.block,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          product.isAvailable ? 'Available' : 'Out of Stock',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    product.category.toUpperCase(),
                    style: TextStyle(color: AppColors.secondary, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                  ),
                  if (product.description != null && product.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      product.description!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  if (product.hasAttributes || product.hasPreferences) ...[
                    FoodAttributesBadge(product: product, compact: true, maxVisible: 2),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.primary,
                            ),
                          ),
                          if (product.servings != null && product.servings! > 0)
                            Text(
                              '${product.servings} servings',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 9),
                            ),
                        ],
                      ),
                      if (hasTiming)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 11, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(
                                '${(product.prepTime ?? 0) + (product.cookTime ?? 0)} min',
                                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}