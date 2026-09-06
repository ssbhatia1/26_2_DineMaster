import sys
import re

screen_file = r'c:\Users\ssbha\Desktop\acccount\26_2_DineMaster\lib\screens\waiter_order_screen.dart'

with open(screen_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add imports at the top
imports = """import 'waiter/waiter_models.dart';
import 'waiter/components/waiter_cart_panel.dart';
import 'waiter/components/waiter_menu_view.dart';
import 'waiter/components/waiter_floor_plan_view.dart';
"""
if "waiter/components/waiter_cart_panel.dart" not in content:
    content = content.replace("import '../widgets/searchable_dropdown.dart';", "import '../widgets/searchable_dropdown.dart';\n" + imports)


# 2. Replace _buildFloorPlanTab()
floor_plan_regex = re.compile(r'  Widget _buildFloorPlanTab\(\) \{.*?\n  // --- FLOOR LEGEND HELPERS ---', re.DOTALL)
if not floor_plan_regex.search(content):
    # wait, the comment below _buildFloorPlanTab is maybe not FLOOR LEGEND HELPERS. Let's just find the next Widget or method.
    floor_plan_regex = re.compile(r'  Widget _buildFloorPlanTab\(\) \{.*?(?=  Widget _buildLegendChip)', re.DOTALL)

new_floor_plan = """  Widget _buildFloorPlanTab() {
    return WaiterFloorPlanView(
      tableInfoList: _tableInfoList,
      sectionsList: _sectionsList,
      selectedSectionFilter: _selectedSectionFilter,
      selectedStatusFilter: _selectedStatusFilter,
      onSectionFilterChanged: (val) => setState(() => _selectedSectionFilter = val),
      onStatusFilterChanged: (val) => setState(() => _selectedStatusFilter = val),
      onTableCardTap: _handleTableCardTap,
    );
  }

"""
content = floor_plan_regex.sub(new_floor_plan, content)

# 3. Replace _buildOrderTakingPanel()
# The panel ends at the end of the class. Let's find it.
order_panel_regex = re.compile(r'  Widget _buildOrderTakingPanel\(\) \{.*\n\}\n$', re.DOTALL)

new_order_panel = """  Widget _buildOrderTakingPanel() {
    final filteredProducts = _products.where((p) {
      final matchesCat = _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();

    return Row(
      children: [
        // Left Side: Catalog
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search Menu Item...',
                    prefixIcon: const Icon(Icons.search),
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                ),
              ),
              Expanded(
                child: WaiterMenuView(
                  categories: _categories,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
                  filteredProducts: filteredProducts,
                  cartItems: _cartItems,
                  onProductTap: _handleProductTap,
                ),
              ),
            ],
          ),
        ),
        
        // Right Side: Cart Panel
        Expanded(
          flex: 3,
          child: WaiterCartPanel(
            orderType: _orderType,
            selectedTableDisplayName: _selectedTableDisplayName,
            selectedTableId: _selectedTableId,
            tableInfoList: _tableInfoList,
            cartItems: _cartItems,
            customerNameController: _customerNameController,
            customerPhoneController: _customerPhoneController,
            waitersList: _waitersList,
            chefsList: _chefsList,
            selectedWaiterId: _selectedWaiterId,
            selectedChefId: _selectedChefId,
            onWaiterSelected: (id, name) => setState(() { _selectedWaiterId = id; _selectedWaiterName = name; }),
            onChefSelected: (id, name) => setState(() { _selectedChefId = id; _selectedChefName = name; }),
            onOrderTypeChanged: (val) {
              setState(() {
                _orderType = val;
                if (_orderType != 'Dine-In') {
                  _selectedTableId = null;
                  _selectedTableDisplayName = 'Takeaway';
                }
              });
            },
            onTableSelected: (tableId) {
              setState(() {
                _selectedTableId = tableId;
                if (tableId != null) {
                  final t = _tableInfoList.firstWhere((ti) => ti.table.id == tableId).table;
                  _selectedTableDisplayName = t.displayName;
                } else {
                  _selectedTableDisplayName = 'Select';
                }
              });
            },
            onDecrementCart: _decrementCart,
            onRemoveCartItem: _removeCartItem,
            onClearCart: () => setState(() => _cartItems.clear()),
            onSendKOT: _submitWaiterOrder,
            onPrintBill: () {},
            onCheckout: () {},
          ),
        ),
      ],
    );
  }
}
"""
content = order_panel_regex.sub(new_order_panel, content)

with open(screen_file, 'w', encoding='utf-8') as f:
    f.write(content)
print("Successfully assembled waiter_order_screen.dart")
