import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../../../models/product_model.dart';
import '../../../widgets/food_attributes_badge.dart';
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
    return Row(
      children: [
        // Left Side: Category Sidebar
        Container(
          width: 100,
          color: Colors.grey.shade50,
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
                    color: isSelected ? AppColors.primaryLight : Colors.transparent,
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
                        color: isSelected ? AppColors.primary : Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Middle: Product Grid View
        Expanded(
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final prod = filteredProducts[index];
                final inCartCount = cartItems.where((it) => it.product.id == prod.id).fold<int>(0, (sum, it) => sum + it.quantity);

                return Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: InkWell(
                    onTap: () => onProductTap(prod),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                Icons.circle,
                                color: prod.isVeg == 1 ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              if (inCartCount > 0)
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text('$inCartCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const Spacer(),

                          // Name
                          Text(
                            prod.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // Food Attributes Badge (compact micro tags)
                          if (prod.hasAttributes || prod.hasPreferences) ...[
                            const SizedBox(height: 4),
                            FoodAttributesBadge(product: prod, compact: true, maxVisible: 2),
                          ],

                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('₹${prod.price}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 15)),
                              Icon(
                                prod.hasPreferences ? Icons.tune : Icons.add_circle,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
