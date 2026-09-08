import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../../../models/product_model.dart';
import '../../../widgets/pos_item_card.dart';
import '../waiter_models.dart';

class WaiterMenuView extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final List<ProductModel> filteredProducts;
  final List<WaiterCartItem> cartItems;
  final Function(ProductModel) onProductTap;

  const WaiterMenuView({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.filteredProducts,
    required this.cartItems,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // Left Side: Category Sidebar
        Container(
          width: 100,
          color: isDark ? const Color(0xFF1E1E24) : Colors.grey.shade50,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = cat == selectedCategory;
              return InkWell(
                onTap: () => onCategorySelected(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? AppColors.primary.withValues(alpha: 0.2) : AppColors.primaryLight)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isSelected ? AppColors.primary : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cat,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Middle: Product Grid View matching POS Billing exactly
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF121214) : Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: filteredProducts.isEmpty
                ? const Center(child: Text('No products found'))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final prod = filteredProducts[index];
                      final inCartCount = cartItems
                          .where((it) => it.product.id == prod.id)
                          .fold<int>(0, (sum, it) => sum + it.quantity);

                      return PosItemCard(
                        product: prod,
                        inCartCount: inCartCount,
                        onTap: () => onProductTap(prod),
                        onInfoTap: () => showProductDetailsDialog(context, prod),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
