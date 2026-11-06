import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../../../widgets/searchable_dropdown.dart';
import '../waiter_models.dart';

class WaiterCartPanel extends StatelessWidget {
  final String orderType;
  final String selectedTableDisplayName;
  final int? selectedTableId;
  final List<WaiterTableInfo> tableInfoList;
  final List<WaiterCartItem> cartItems;
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final List<Map<String, dynamic>> waitersList;
  final List<Map<String, dynamic>> chefsList;
  final int? selectedWaiterId;
  final int? selectedChefId;
  final Function(int?, String?) onWaiterSelected;
  final Function(int?, String?) onChefSelected;
  
  // Callbacks
  final Function(String) onOrderTypeChanged;
  final Function(int?) onTableSelected;
  final ValueChanged<int> onDecrementCart;
  final ValueChanged<int> onRemoveCartItem;
  final ValueChanged<int>? onEditCartItem;
  final VoidCallback onClearCart;
  final VoidCallback onSendKOT;
  final VoidCallback onPrintBill;
  final VoidCallback onCheckout;
  final bool showWaiterAssignment;
  final bool showChefAssignment;

  const WaiterCartPanel({
    super.key,
    required this.orderType,
    required this.selectedTableDisplayName,
    required this.selectedTableId,
    required this.tableInfoList,
    required this.cartItems,
    required this.customerNameController,
    required this.customerPhoneController,
    required this.waitersList,
    required this.chefsList,
    required this.selectedWaiterId,
    required this.selectedChefId,
    required this.onWaiterSelected,
    required this.onChefSelected,
    required this.onOrderTypeChanged,
    required this.onTableSelected,
    required this.onDecrementCart,
    required this.onRemoveCartItem,
    this.onEditCartItem,
    required this.onClearCart,
    required this.onSendKOT,
    required this.onPrintBill,
    required this.onCheckout,
    this.showWaiterAssignment = true,
    this.showChefAssignment = true,
  });

  double get subtotal => cartItems.fold(0.0, (sum, it) => sum + it.subtotal);
  double get total => subtotal; // Assuming no extra taxes calculated here for now

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Order Setup Header
          Text(
            orderType == 'Dine-In' ? 'Order: $selectedTableDisplayName' : 'New Order - Takeaway',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
          ),
          const SizedBox(height: 16),

          // Order Type & Table Selection
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: orderType,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Type', isDense: true),
                  items: ['Dine-In', 'Takeaway', 'Delivery'].map((type) {
                    return DropdownMenuItem<String>(value: type, child: Text(type, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) onOrderTypeChanged(val);
                  },
                ),
              ),
              if (orderType == 'Dine-In') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SearchableDropdown<WaiterTableInfo>(
                    // Show only merged group anchors so a merged group is picked
                    // as a single entity for order taking.
                    items: tableInfoList.where((ti) => ti.table.mergedWithId == null).toList(),
                    value: selectedTableId != null && tableInfoList.any((ti) => ti.table.id == selectedTableId)
                        ? tableInfoList.firstWhere((ti) => ti.table.id == selectedTableId)
                        : null,
                    labelText: 'Table',
                    hintText: 'Select...',
                    itemToString: (ti) => ti.mergedTables.isNotEmpty
                        ? '${ti.mergedTableNumbers} (Merged • ${ti.table.status})'
                        : '${ti.table.displayName} (${ti.table.status})',
                    filterFn: (ti, query) => (ti.displayNameForOrder).toLowerCase().contains(query.toLowerCase()),
                    onChanged: (val) {
                      onTableSelected(val?.table.id);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          if (orderType != 'Dine-In') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customerNameController,
                    decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: customerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],


          // Waiter & Chef assignment
          if (showWaiterAssignment || showChefAssignment) ...[
            Row(
              children: [
                if (showWaiterAssignment)
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
                if (showWaiterAssignment && showChefAssignment)
                  const SizedBox(width: 8),
                if (showChefAssignment)
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
          ],
          
          const Divider(),

          // Cart Items List
          Expanded(
            child: cartItems.isEmpty
                ? const Center(child: Text('Cart is empty', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: cartItems.length,
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            // Quantity Controls
                            Column(
                              children: [
                                InkWell(
                                  onTap: () => onDecrementCart(index),
                                  child: const Icon(Icons.remove_circle_outline, color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(height: 4),
                                Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(width: 12),

                            // Item Details
                            Expanded(
                              child: InkWell(
                                onTap: onEditCartItem != null ? () => onEditCartItem!(index) : null,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    if (item.formattedNotes.isNotEmpty)
                                      Text(
                                        item.formattedNotes,
                                        style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
                                      ),
                                    const SizedBox(height: 4),
                                    const Text('Tap to edit notes/preferences', style: TextStyle(color: Colors.grey, fontSize: 9)),
                                  ],
                                ),
                              ),
                            ),

                            // Price and Delete
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('₹${item.subtotal}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                InkWell(
                                  onTap: () => onRemoveCartItem(index),
                                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Subtotals and Actions
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('₹${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 16),

          // Primary Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: cartItems.isEmpty ? null : onSendKOT,
                  icon: const Icon(Icons.kitchen),
                  label: const Text('Send KOT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cartItems.isEmpty ? null : onPrintBill,
                  icon: const Icon(Icons.receipt),
                  label: const Text('Print Bill'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: cartItems.isEmpty ? null : onCheckout,
                  icon: const Icon(Icons.payment),
                  label: const Text('Checkout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: cartItems.isEmpty ? null : onClearCart,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );
  }
}
