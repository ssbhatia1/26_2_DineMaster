import 'package:flutter/material.dart';
import '../models/product_model.dart';

class FoodAttributesBadge extends StatelessWidget {
  final ProductModel product;
  final bool compact;
  final int maxVisible;

  const FoodAttributesBadge({
    super.key,
    required this.product,
    this.compact = true,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> badges = [];

    // 1. Dietary Badges (Pure Jain, Semi Jain)
    for (var pref in product.dietaryPreferences) {
      if (pref == 'Pure Jain') {
        badges.add(_buildBadge(
          label: 'Pure Jain',
          icon: Icons.spa,
          bgColor: const Color(0xFFE8F5E9),
          textColor: const Color(0xFF2E7D32),
          borderColor: const Color(0xFFA5D6A7),
        ));
      } else if (pref == 'Semi Jain') {
        badges.add(_buildBadge(
          label: 'Semi Jain',
          icon: Icons.eco,
          bgColor: const Color(0xFFE0F2F1),
          textColor: const Color(0xFF00695C),
          borderColor: const Color(0xFF80CBC4),
        ));
      }
    }

    // 2. Taste Badges (Sweet, Spicy, Extra Spicy)
    for (var taste in product.tastePreferences) {
      if (taste == 'Sweet') {
        badges.add(_buildBadge(
          label: 'Sweet',
          icon: Icons.cake_outlined,
          bgColor: const Color(0xFFFCE4EC),
          textColor: const Color(0xFFC2185B),
          borderColor: const Color(0xFFF48FB1),
        ));
      } else if (taste == 'Spicy') {
        badges.add(_buildBadge(
          label: 'Spicy',
          icon: Icons.whatshot,
          bgColor: const Color(0xFFFFF3E0),
          textColor: const Color(0xFFE65100),
          borderColor: const Color(0xFFFFCC80),
        ));
      } else if (taste == 'Extra Spicy') {
        badges.add(_buildBadge(
          label: 'Extra Spicy',
          icon: Icons.local_fire_department,
          bgColor: const Color(0xFFFFEBEE),
          textColor: const Color(0xFFB71C1C),
          borderColor: const Color(0xFFEF9A9A),
        ));
      }
    }

    // 3. Highlight Food Attributes
    for (var attr in product.attributes) {
      switch (attr) {
        case "Chef's Special":
          badges.add(_buildBadge(
            label: "Chef's Special",
            icon: Icons.star_rounded,
            bgColor: const Color(0xFFFFF8E1),
            textColor: const Color(0xFFF57F17),
            borderColor: const Color(0xFFFFE082),
          ));
          break;
        case "Bestseller":
          badges.add(_buildBadge(
            label: "Bestseller",
            icon: Icons.trending_up_rounded,
            bgColor: const Color(0xFFFFF3E0),
            textColor: const Color(0xFFD84315),
            borderColor: const Color(0xFFFFAB91),
          ));
          break;
        case "Recommended":
          badges.add(_buildBadge(
            label: "Recommended",
            icon: Icons.thumb_up_alt_outlined,
            bgColor: const Color(0xFFEDE7F6),
            textColor: const Color(0xFF512DA8),
            borderColor: const Color(0xFFD1C4E9),
          ));
          break;
        case "New":
          badges.add(_buildBadge(
            label: "New",
            icon: Icons.auto_awesome,
            bgColor: const Color(0xFFE0F7FA),
            textColor: const Color(0xFF00838F),
            borderColor: const Color(0xFF80DEEA),
          ));
          break;
        case "Popular":
          badges.add(_buildBadge(
            label: "Popular",
            icon: Icons.favorite,
            bgColor: const Color(0xFFFCE4EC),
            textColor: const Color(0xFFAD1457),
            borderColor: const Color(0xFFF8BBD0),
          ));
          break;
        case "Healthy":
          badges.add(_buildBadge(
            label: "Healthy",
            icon: Icons.health_and_safety_outlined,
            bgColor: const Color(0xFFE8F5E9),
            textColor: const Color(0xFF2E7D32),
            borderColor: const Color(0xFFA5D6A7),
          ));
          break;
        case "Vegan":
          badges.add(_buildBadge(
            label: "Vegan",
            icon: Icons.grass,
            bgColor: const Color(0xFFE8F5E9),
            textColor: const Color(0xFF1B5E20),
            borderColor: const Color(0xFF81C784),
          ));
          break;
        case "Gluten-Free":
          badges.add(_buildBadge(
            label: "Gluten-Free",
            icon: Icons.grain,
            bgColor: const Color(0xFFEFEBE9),
            textColor: const Color(0xFF4E342E),
            borderColor: const Color(0xFFBCAAA4),
          ));
          break;
        case "Contains Dairy":
          badges.add(_buildBadge(
            label: "Dairy",
            icon: Icons.water_drop_outlined,
            bgColor: const Color(0xFFE3F2FD),
            textColor: const Color(0xFF1565C0),
            borderColor: const Color(0xFF90CAF9),
          ));
          break;
        case "Contains Nuts":
          badges.add(_buildBadge(
            label: "Nuts",
            icon: Icons.cookie_outlined,
            bgColor: const Color(0xFFFFF3E0),
            textColor: const Color(0xFFE65100),
            borderColor: const Color(0xFFFFCC80),
          ));
          break;
        default:
          if (attr.isNotEmpty) {
            badges.add(_buildBadge(
              label: attr,
              icon: Icons.label_outline,
              bgColor: Colors.grey.shade100,
              textColor: Colors.grey.shade800,
              borderColor: Colors.grey.shade300,
            ));
          }
      }
    }

    // 4. Custom Dietary Notes
    if (product.customDietaryNotes != null && product.customDietaryNotes!.trim().isNotEmpty) {
      badges.add(Tooltip(
        message: product.customDietaryNotes!,
        child: _buildBadge(
          label: product.customDietaryNotes!,
          icon: Icons.info_outline,
          bgColor: const Color(0xFFF3E5F5),
          textColor: const Color(0xFF6A1B9A),
          borderColor: const Color(0xFFCE93D8),
        ),
      ));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    if (compact && badges.length > maxVisible) {
      final visible = badges.take(maxVisible).toList();
      visible.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '+${badges.length - maxVisible}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      );
      return Wrap(
        spacing: 4,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: visible,
      );
    }

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: badges,
    );
  }

  Widget _buildBadge({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 9.5 : 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
