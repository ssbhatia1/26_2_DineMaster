import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../models/product_model.dart';
import 'food_attributes_badge.dart';

/// Reusable Product Card designed for POS Billing, Take Order, and Menu grids.
/// Matches the standard POS item card layout, styling, typography, and badges.
class PosItemCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;
  final int inCartCount;
  final Widget? trailingTopAction;

  const PosItemCard({
    super.key,
    required this.product,
    this.onTap,
    this.onInfoTap,
    this.inCartCount = 0,
    this.trailingTopAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAvailable = product.isAvailable;

    Color typeColor = Colors.red;
    if (product.isVeg == 1) {
      typeColor = Colors.green;
    } else if (product.isVeg == 2) {
      typeColor = Colors.orange;
    } else if (product.isVeg == 3) {
      typeColor = Colors.blue;
    }

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: isAvailable ? 1.0 : 0.5,
        child: InkWell(
          onTap: isAvailable ? onTap : null,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top row: Veg dot indicator + in-cart count / info / actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(color: typeColor.withValues(alpha: 0.4), width: 1.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: typeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (inCartCount > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$inCartCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (onInfoTap != null)
                              IconButton(
                                icon: const Icon(Icons.info_outline, color: Colors.grey, size: 18),
                                onPressed: onInfoTap,
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                              ),
                            ?trailingTopAction,
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Middle Graphic: Circle food icon
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade800.withValues(alpha: 0.5)
                              : AppColors.primaryLight.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          product.isVeg == 1 ? Icons.local_pizza : Icons.lunch_dining,
                          size: 36,
                          color: AppColors.primaryMaterialColor[300]!,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Bottom info: Name, badges, price & category
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.grey.shade800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (product.hasAttributes || product.hasPreferences) ...[
                          const SizedBox(height: 3),
                          FoodAttributesBadge(product: product, compact: true, maxVisible: 2),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '₹${product.price}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  product.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sold out overlay
              if (!isAvailable)
                Container(
                  color: Colors.black.withValues(alpha: 0.05),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'SOLD OUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper function to display detailed product information modal across POS, Take Order, etc.
void showProductDetailsDialog(BuildContext context, ProductModel product) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Category: ${product.category}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: product.isAvailable ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    product.isAvailable ? 'Available' : 'Out of Stock',
                    style: TextStyle(
                      color: product.isAvailable ? Colors.green.shade700 : Colors.red.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Price: ₹${product.price}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
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
                              ? Colors.blue
                              : Colors.red)),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  product.isVeg == 1
                      ? 'Veg'
                      : (product.isVeg == 2
                          ? 'Egg'
                          : (product.isVeg == 3
                              ? 'Jain'
                              : 'Non-Veg')),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              product.description ?? 'No description available.',
              style: const TextStyle(color: Colors.black87),
            ),
            if (product.ingredients != null && product.ingredients!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Ingredients:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: product.ingredients!
                    .split(',')
                    .where((s) => s.trim().isNotEmpty)
                    .map((ing) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ing.trim(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            if (product.customDietaryNotes != null && product.customDietaryNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Dietary Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                product.customDietaryNotes!,
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
