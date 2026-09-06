import sys
import re

cart_file = r'c:\Users\ssbha\Desktop\acccount\26_2_DineMaster\lib\screens\waiter\components\waiter_cart_panel.dart'

with open(cart_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Need to add waiter and chef lists and callbacks to constructor
class_def = """  final List<Map<String, dynamic>> waitersList;
  final List<Map<String, dynamic>> chefsList;
  final int? selectedWaiterId;
  final int? selectedChefId;
  final Function(int?, String?) onWaiterSelected;
  final Function(int?, String?) onChefSelected;"""

content = content.replace("  final TextEditingController customerPhoneController;", "  final TextEditingController customerPhoneController;\n" + class_def)

constructor_additions = """    required this.waitersList,
    required this.chefsList,
    required this.selectedWaiterId,
    required this.selectedChefId,
    required this.onWaiterSelected,
    required this.onChefSelected,"""

content = content.replace("    required this.customerPhoneController,", "    required this.customerPhoneController,\n" + constructor_additions)


# Now add the UI components below the Customer Name / Phone row
dropdowns_ui = """
          // Waiter & Chef assignment
          Row(
            children: [
              Expanded(
                child: SearchableDropdown<Map<String, dynamic>>(
                  items: waitersList,
                  value: selectedWaiterId != null && waitersList.any((w) => w['id'] == selectedWaiterId)
                      ? waitersList.firstWhere((w) => w['id'] == selectedWaiterId)
                      : null,
                  labelText: 'Waiter',
                  hintText: 'Select Waiter',
                  itemToString: (w) => w['name'] as String? ?? '',
                  filterFn: (w, query) => (w['name'] as String? ?? '').toLowerCase().contains(query.toLowerCase()),
                  onChanged: (val) => onWaiterSelected(val?['id'] as int?, val?['name'] as String?),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SearchableDropdown<Map<String, dynamic>>(
                  items: chefsList,
                  value: selectedChefId != null && chefsList.any((c) => c['id'] == selectedChefId)
                      ? chefsList.firstWhere((c) => c['id'] == selectedChefId)
                      : null,
                  labelText: 'Chef',
                  hintText: 'Select Chef',
                  itemToString: (c) => c['name'] as String? ?? '',
                  filterFn: (c, query) => (c['name'] as String? ?? '').toLowerCase().contains(query.toLowerCase()),
                  onChanged: (val) => onChefSelected(val?['id'] as int?, val?['name'] as String?),
                  prefixIcon: const Icon(Icons.restaurant_menu),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
"""

content = content.replace("          const Divider(),\n\n          // Cart Items List", dropdowns_ui + "          const Divider(),\n\n          // Cart Items List")

# Adjust buttons to only be Send KOT
buttons = """
          // Primary Actions
          ElevatedButton(
            onPressed: cartItems.isEmpty ? null : onSendKOT,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Send Order to Kitchen (KOT)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
"""

old_buttons_regex = r"          // Primary Actions.*Clear Cart'\),\n        \],\n      \),\n    \);\n  \}\n\}"
content = re.sub(old_buttons_regex, buttons + "        ],\n      ),\n    );\n  }\n}", content, flags=re.DOTALL)

with open(cart_file, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated waiter_cart_panel.dart")
