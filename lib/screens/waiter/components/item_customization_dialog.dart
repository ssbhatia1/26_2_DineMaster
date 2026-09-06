import 'package:flutter/material.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import '../../models/product_model.dart';

class ItemCustomizationDialog extends StatefulWidget {
  final ProductModel product;

  const ItemCustomizationDialog({super.key, required this.product});

  @override
  State<ItemCustomizationDialog> createState() => _ItemCustomizationDialogState();
}

class _ItemCustomizationDialogState extends State<ItemCustomizationDialog> {
  String? selectedDietary;
  String? selectedTaste;
  int quantity = 1;
  final notesCtrl = TextEditingController();

  @override
  void dispose() {
    notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.tune, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.product.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dietary Preferences
            if (widget.product.dietaryPreferences.isNotEmpty) ...[
              const Text('Dietary Preference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Regular'),
                    selected: selectedDietary == null,
                    onSelected: (val) => setState(() => selectedDietary = null),
                  ),
                  ...widget.product.dietaryPreferences.map((pref) {
                    return ChoiceChip(
                      label: Text(pref),
                      selected: selectedDietary == pref,
                      selectedColor: Colors.green.shade100,
                      onSelected: (val) => setState(() => selectedDietary = val ? pref : null),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Taste Profile
            if (widget.product.tastePreferences.isNotEmpty) ...[
              const Text('Taste Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Default'),
                    selected: selectedTaste == null,
                    onSelected: (val) => setState(() => selectedTaste = null),
                  ),
                  ...widget.product.tastePreferences.map((taste) {
                    return ChoiceChip(
                      label: Text(taste),
                      selected: selectedTaste == taste,
                      selectedColor: Colors.deepOrange.shade100,
                      onSelected: (val) => setState(() => selectedTaste = val ? taste : null),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Custom Dietary Notes
            if (widget.product.customDietaryNotes != null && widget.product.customDietaryNotes!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.purple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.product.customDietaryNotes!,
                        style: const TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Quantity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      color: Colors.red,
                      onPressed: () {
                        if (quantity > 1) setState(() => quantity--);
                      },
                    ),
                    Text('$quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: Colors.green,
                      onPressed: () => setState(() => quantity++),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Additional Notes
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Additional Notes (Optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.pop(context, {
              'dietaryPreference': selectedDietary,
              'tastePreference': selectedTaste,
              'notes': notesCtrl.text,
              'quantity': quantity,
            });
          },
          child: const Text('Add to Cart'),
        ),
      ],
    );
  }
}
