import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';
import '../models/product_model.dart';
import '../models/table_model.dart';
import '../repositories/product_repository.dart';
import '../services/sync_service.dart';
import '../widgets/searchable_dropdown.dart';
import '../widgets/food_attributes_badge.dart';

/// Representation of a customized cart item for the waiter
class _WaiterCartItem {
  final ProductModel product;
  int quantity;
  String? dietaryPreference;
  String? tastePreference;
  String? notes;

  _WaiterCartItem({
    required this.product,
    this.quantity = 1,
    this.dietaryPreference,
    this.tastePreference,
    this.notes,
  });

  String get formattedNotes {
    final List<String> parts = [];
    if (dietaryPreference != null && dietaryPreference!.isNotEmpty) {
      parts.add('[$dietaryPreference]');
    }
    if (tastePreference != null && tastePreference!.isNotEmpty) {
      parts.add('[$tastePreference]');
    }
    if (notes != null && notes!.trim().isNotEmpty) {
      parts.add(notes!.trim());
    }
    return parts.join(' ');
  }

  double get subtotal => product.price * quantity;
}

/// Enriched table container for waiter floor plan
class _WaiterTableInfo {
  final TableModel table;
  final Map<String, dynamic>? activeOrder;
  final int orderItemsCount;

  _WaiterTableInfo({
    required this.table,
    this.activeOrder,
    this.orderItemsCount = 0,
  });
}

class WaiterOrderScreen extends StatefulWidget {
  const WaiterOrderScreen({super.key});

  @override
  State<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

class _WaiterOrderScreenState extends State<WaiterOrderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductRepository _productRepository = ProductRepository();

  bool _isLoading = true;
  bool _isTakingOrder = false;

  // Floor Plan States
  List<_WaiterTableInfo> _tableInfoList = [];
  String _selectedSectionFilter = 'All';
  String _selectedStatusFilter = 'All';
  List<String> _sectionsList = ['All'];

  // Waiter Orders & Staff
  List<Map<String, dynamic>> _waiterOrdersList = [];
  List<Map<String, dynamic>> _chefsList = [];
  List<Map<String, dynamic>> _waitersList = [];

  // Staff Selection States
  int? _selectedWaiterId;
  String? _selectedWaiterName;
  int? _selectedChefId;
  String? _selectedChefName;

  // Order Taking States
  List<ProductModel> _products = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';
  String _searchQuery = '';

  // Active Cart details
  int? _selectedTableId;
  String _selectedTableDisplayName = 'Select';
  String _orderType = 'Dine-In';
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();

  // Cart list
  final List<_WaiterCartItem> _cartItems = [];

  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDashboardAndProducts();

    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted) {
        _loadDashboardAndProducts();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardAndProducts() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;

      // 1. Fetch tables and active orders
      final List<Map<String, dynamic>> tablesResult = await db.query(
        'tables',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );

      final List<_WaiterTableInfo> enrichedTables = [];
      final Set<String> sections = {'All'};

      for (var tMap in tablesResult) {
        final table = TableModel.fromMap(tMap);
        if (table.section.isNotEmpty) {
          sections.add(table.section);
        }

        // Check active order
        final List<Map<String, dynamic>> activeOrders = await db.query(
          'orders',
          where: 'table_id = ? AND status IN (\'Received\', \'Sent to Kitchen\', \'Preparing\', \'Ready\', \'Served\', \'Billing Pending\') AND restaurant_id = ?',
          whereArgs: [table.id, restaurantId],
          orderBy: 'id DESC',
          limit: 1,
        );

        Map<String, dynamic>? activeOrder = activeOrders.isNotEmpty ? activeOrders.first : null;
        int itemsCount = 0;

        if (activeOrder != null) {
          final items = await db.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [activeOrder['id']],
          );
          itemsCount = items.fold(0, (sum, it) => sum + (it['quantity'] as int? ?? 1));
        }

        enrichedTables.add(_WaiterTableInfo(
          table: table,
          activeOrder: activeOrder,
          orderItemsCount: itemsCount,
        ));
      }

      _tableInfoList = enrichedTables;
      _sectionsList = sections.toList();

      // 2. Fetch products
      final products = await _productRepository.getProducts();
      _products = products.where((p) => p.isAvailable).toList();

      // Extract categories
      final Set<String> catSet = {'All'};
      for (var p in _products) {
        if (p.category.isNotEmpty) {
          catSet.add(p.category);
        }
      }
      _categories = catSet.toList();

      // 3. Fetch waiter active orders
      final List<Map<String, dynamic>> ordersResult = await db.rawQuery('''
        SELECT o.*, t.table_number, t.name as table_name, t.section as table_section
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.status IN ('Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served', 'Billing Pending')
        AND o.restaurant_id = ?
        ORDER BY o.id DESC
      ''', [restaurantId]);
      _waiterOrdersList = List<Map<String, dynamic>>.from(ordersResult);

      // 4. Fetch chefs and waiters list
      final List<Map<String, dynamic>> chefsResult = await db.query(
        'users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['Chef'],
      );
      _chefsList = List<Map<String, dynamic>>.from(chefsResult);

      final List<Map<String, dynamic>> waitersResult = await db.query(
        'users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['Waiter'],
      );
      _waitersList = List<Map<String, dynamic>>.from(waitersResult);

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      if (username != null && _selectedWaiterId == null) {
        final matchedWaiters = _waitersList.where((w) => w['username'] == username);
        if (matchedWaiters.isNotEmpty) {
          _selectedWaiterId = matchedWaiters.first['id'] as int?;
          _selectedWaiterName = matchedWaiters.first['name'] as String?;
        }
      }
    } catch (e) {
      debugPrint('Error loading waiter configurations: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- CART MANAGEMENT ---
  void _handleProductTap(ProductModel product) {
    if (product.hasPreferences) {
      _showPreferenceCustomizationDialog(product);
    } else {
      _addToCart(product);
    }
  }

  void _addToCart(
    ProductModel product, {
    String? dietaryPreference,
    String? tastePreference,
    String? notes,
    int qty = 1,
  }) {
    setState(() {
      final index = _cartItems.indexWhere(
        (it) =>
            it.product.id == product.id &&
            it.dietaryPreference == dietaryPreference &&
            it.tastePreference == tastePreference &&
            it.notes == notes,
      );

      if (index >= 0) {
        _cartItems[index].quantity += qty;
      } else {
        _cartItems.add(_WaiterCartItem(
          product: product,
          quantity: qty,
          dietaryPreference: dietaryPreference,
          tastePreference: tastePreference,
          notes: notes,
        ));
      }
    });
  }

  void _decrementCart(int index) {
    setState(() {
      if (index >= 0 && index < _cartItems.length) {
        if (_cartItems[index].quantity > 1) {
          _cartItems[index].quantity--;
        } else {
          _cartItems.removeAt(index);
        }
      }
    });
  }

  void _removeCartItem(int index) {
    setState(() {
      if (index >= 0 && index < _cartItems.length) {
        _cartItems.removeAt(index);
      }
    });
  }

  double _calculateSubtotal() {
    return _cartItems.fold(0.0, (sum, it) => sum + it.subtotal);
  }

  // --- ITEM CUSTOMIZATION DIALOG ---
  void _showPreferenceCustomizationDialog(ProductModel product) {
    String? selectedDietary;
    String? selectedTaste;
    int quantity = 1;
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.tune, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.name,
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
                // Dietary Preferences (Filtered to only what is configured for this dish)
                if (product.dietaryPreferences.isNotEmpty) ...[
                  const Text('Dietary Preference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Regular'),
                        selected: selectedDietary == null,
                        onSelected: (val) => setDlgState(() => selectedDietary = null),
                      ),
                      ...product.dietaryPreferences.map((pref) {
                        return ChoiceChip(
                          label: Text(pref),
                          selected: selectedDietary == pref,
                          selectedColor: Colors.green.shade100,
                          onSelected: (val) => setDlgState(() => selectedDietary = val ? pref : null),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Taste Profile (Filtered to only what is configured for this dish)
                if (product.tastePreferences.isNotEmpty) ...[
                  const Text('Taste Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Default'),
                        selected: selectedTaste == null,
                        onSelected: (val) => setDlgState(() => selectedTaste = null),
                      ),
                      ...product.tastePreferences.map((taste) {
                        return ChoiceChip(
                          label: Text(taste),
                          selected: selectedTaste == taste,
                          selectedColor: Colors.deepOrange.shade100,
                          onSelected: (val) => setDlgState(() => selectedTaste = val ? taste : null),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Custom Dietary Notes from Admin
                if (product.customDietaryNotes != null && product.customDietaryNotes!.trim().isNotEmpty) ...[
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
                            product.customDietaryNotes!,
                            style: const TextStyle(fontSize: 12, color: Colors.purple),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Kitchen Instructions
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen Instructions / Notes',
                    hintText: 'e.g. Less oil, extra spicy, crispy...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Quantity Picker
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: quantity > 1 ? () => setDlgState(() => quantity--) : null,
                        ),
                        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDlgState(() => quantity++),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _addToCart(
                  product,
                  dietaryPreference: selectedDietary,
                  tastePreference: selectedTaste,
                  notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  qty: quantity,
                );
              },
              child: const Text('Add to Order'),
            ),
          ],
        ),
      ),
    );
  }

  // --- QUICK WATER & SERVICE REQUEST MODAL ---
  Future<void> _showQuickWaterServiceDialog({TableModel? preselectedTable}) async {
    TableModel? selectedTable = preselectedTable;
    if (selectedTable == null && _tableInfoList.isNotEmpty) {
      selectedTable = _tableInfoList.first.table;
    }

    String selectedWaterType = 'Chilled Drinking Water';
    int glassesCount = 2;
    bool requestCutlery = false;
    bool requestTissues = false;
    bool requestSaltPepper = false;
    final specialInstructionsCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.water_drop, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick Water & Service Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Dispatch instant drinking water & essentials', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table Selector
                  if (preselectedTable == null) ...[
                    DropdownButtonFormField<int>(
                      initialValue: selectedTable?.id,
                      decoration: const InputDecoration(
                        labelText: 'Select Destination Table',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.table_restaurant),
                      ),
                      items: _tableInfoList.map((ti) {
                        return DropdownMenuItem<int>(
                          value: ti.table.id,
                          child: Text('${ti.table.displayName} • ${ti.table.section} (${ti.table.status})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedTable = _tableInfoList.firstWhere((ti) => ti.table.id == val).table;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.table_restaurant, color: Colors.deepPurple, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Serving: ${preselectedTable.displayName} (${preselectedTable.section})',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Water Type Selection
                  const Text('Water Selection:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildWaterOptionChip('Chilled Drinking Water', Icons.ac_unit, Colors.blue, selectedWaterType, (val) {
                        setModalState(() => selectedWaterType = val);
                      }),
                      _buildWaterOptionChip('Room Temp Filtered Water', Icons.water_drop_outlined, Colors.teal, selectedWaterType, (val) {
                        setModalState(() => selectedWaterType = val);
                      }),
                      _buildWaterOptionChip('Warm / Hot Water', Icons.coffee, Colors.orange, selectedWaterType, (val) {
                        setModalState(() => selectedWaterType = val);
                      }),
                      _buildWaterOptionChip('Packaged Mineral Water (1L - ₹20)', Icons.local_drink, Colors.purple, selectedWaterType, (val) {
                        setModalState(() => selectedWaterType = val);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Glass Count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Number of Glasses:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [1, 2, 4, 6, 8].map((count) {
                          final isSelected = glassesCount == count;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4.0),
                            child: ChoiceChip(
                              label: Text('$count'),
                              selected: isSelected,
                              selectedColor: Colors.blue.shade100,
                              onSelected: (val) => setModalState(() => glassesCount = count),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Additional Table Essentials
                  const Text('Table Essentials & Refills:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    title: const Text('Extra Cutlery & Spoons', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: requestCutlery,
                    onChanged: (val) => setModalState(() => requestCutlery = val ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('Napkins & Tissue Refill', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: requestTissues,
                    onChanged: (val) => setModalState(() => requestTissues = val ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('Extra Salt & Pepper Dispenser', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: requestSaltPepper,
                    onChanged: (val) => setModalState(() => requestSaltPepper = val ?? false),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: specialInstructionsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Special Note (Optional)',
                      hintText: 'e.g. Ice on the side, lemon slice...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Dispatch Water Request', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: selectedTable == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _dispatchWaterServiceRequest(
                        table: selectedTable!,
                        waterType: selectedWaterType,
                        glasses: glassesCount,
                        cutlery: requestCutlery,
                        tissues: requestTissues,
                        saltPepper: requestSaltPepper,
                        notes: specialInstructionsCtrl.text.trim(),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterOptionChip(String title, IconData icon, Color color, String selectedValue, ValueChanged<String> onSelected) {
    final isSelected = selectedValue == title;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
      label: Text(title, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.15),
      onSelected: (val) {
        if (val) onSelected(title);
      },
    );
  }

  Future<void> _dispatchWaterServiceRequest({
    required TableModel table,
    required String waterType,
    required int glasses,
    required bool cutlery,
    required bool tissues,
    required bool saltPepper,
    required String notes,
  }) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;
      final String now = DateTime.now().toIso8601String();

      // Check if table has an active order
      final List<Map<String, dynamic>> existingOrders = await db.query(
        'orders',
        where: 'table_id = ? AND status IN (\'Received\', \'Sent to Kitchen\', \'Preparing\', \'Ready\', \'Served\') AND restaurant_id = ?',
        whereArgs: [table.id, restaurantId],
        orderBy: 'id DESC',
        limit: 1,
      );

      final isPaidMineralWater = waterType.contains('Mineral Water');
      final double waterPrice = isPaidMineralWater ? 20.0 : 0.0;

      // Find or create a product item for tracking in order_items
      int waterProductId;
      final String prodName = isPaidMineralWater ? 'Packaged Mineral Water (1L)' : 'Table Drinking Water';
      final existingProds = await db.query(
        'products',
        where: 'name = ? AND restaurant_id = ?',
        whereArgs: [prodName, restaurantId],
        limit: 1,
      );

      if (existingProds.isNotEmpty) {
        waterProductId = existingProds.first['id'] as int;
      } else {
        waterProductId = await db.insert('products', {
          'name': prodName,
          'price': waterPrice,
          'category': 'Beverages',
          'is_veg': 1,
          'is_available': 1,
          'prep_time': 2,
          'cook_time': 1,
          'restaurant_id': restaurantId,
        });
      }

      // Build service instructions summary
      final List<String> serviceItems = ['$waterType ($glasses Glasses)'];
      if (cutlery) serviceItems.add('Extra Cutlery');
      if (tissues) serviceItems.add('Napkin Refill');
      if (saltPepper) serviceItems.add('Salt/Pepper');
      if (notes.isNotEmpty) serviceItems.add('Note: $notes');

      final String fullServiceNote = '[WATER SERVICE] ${serviceItems.join(" • ")}';

      int orderId;
      if (existingOrders.isNotEmpty) {
        // Append to existing active order
        orderId = existingOrders.first['id'] as int;

        await db.insert('order_items', {
          'order_id': orderId,
          'product_id': waterProductId,
          'quantity': 1,
          'price': waterPrice,
          'status': 'Pending',
          'notes': fullServiceNote,
        });

        if (isPaidMineralWater) {
          final prevTotal = (existingOrders.first['total_amount'] as num).toDouble();
          final newTotal = prevTotal + (waterPrice * 1.05); // 5% tax
          await db.update('orders', {'total_amount': newTotal}, where: 'id = ?', whereArgs: [orderId]);
        }
      } else {
        // Table does not have active order -> Create a new seated session
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Waiter';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        orderId = await db.insert('orders', {
          'total_amount': isPaidMineralWater ? waterPrice * 1.05 : 0.0,
          'status': 'Received',
          'type': 'Dine-In',
          'order_time': now,
          'restaurant_id': restaurantId,
          'table_id': table.id,
          'customer_name': 'Guest (${table.tableNumber})',
          'payment_status': 'Unpaid',
          'discount_amount': 0.0,
          'order_taker_name': _selectedWaiterName ?? orderTakerName,
          'order_taker_id': _selectedWaiterId ?? orderTakerId,
          'notes': fullServiceNote,
        });

        await db.insert('order_items', {
          'order_id': orderId,
          'product_id': waterProductId,
          'quantity': 1,
          'price': waterPrice,
          'status': 'Pending',
          'notes': fullServiceNote,
        });

        // Mark table as Occupied
        await db.update(
          'tables',
          {'status': 'Occupied'},
          where: 'id = ?',
          whereArgs: [table.id],
        );
      }

      // Generate KOT so service / beverage station is alerted
      await DatabaseHelper.instance.generateKOTForOrder(orderId, _selectedChefName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Water & Service Request dispatched for ${table.displayName}! (Order #$orderId)'),
              ),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 3),
        ),
      );

      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to dispatch water request: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- SUBMIT WAITER ORDER (KOT) ---
  Future<void> _submitWaiterOrder() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot place empty order.')),
      );
      return;
    }

    if (_orderType == 'Dine-In' && _selectedTableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a table for Dine-In orders.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;
      final String now = DateTime.now().toIso8601String();

      // Check if table already has an active order
      int orderId;
      List<Map<String, dynamic>> existingOrder = [];

      if (_orderType == 'Dine-In' && _selectedTableId != null) {
        existingOrder = await db.query(
          'orders',
          where: 'table_id = ? AND status IN (\'Received\', \'Sent to Kitchen\', \'Preparing\', \'Ready\', \'Served\') AND restaurant_id = ?',
          whereArgs: [_selectedTableId, restaurantId],
        );
      }

      if (existingOrder.isNotEmpty) {
        // Append items to existing order
        orderId = existingOrder.first['id'] as int;

        for (var item in _cartItems) {
          final note = item.formattedNotes;
          await db.insert('order_items', {
            'order_id': orderId,
            'product_id': item.product.id,
            'quantity': item.quantity,
            'price': item.product.price,
            'status': 'Pending',
            'notes': note.isNotEmpty ? note : null,
          });
        }

        final double subtotal = _calculateSubtotal();
        final double prevTotal = (existingOrder.first['total_amount'] as num).toDouble();
        final double newTotal = prevTotal + (subtotal * 1.05);

        await db.update(
          'orders',
          {'total_amount': newTotal},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      } else {
        final double subtotal = _calculateSubtotal();
        final double total = subtotal * 1.05;

        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Waiter';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        orderId = await db.insert('orders', {
          'total_amount': total,
          'status': 'Sent to Kitchen',
          'type': _orderType,
          'order_time': now,
          'restaurant_id': restaurantId,
          'table_id': _selectedTableId,
          'customer_name': _customerNameController.text.trim().isNotEmpty ? _customerNameController.text.trim() : 'Guest',
          'customer_phone': _customerPhoneController.text.trim().isNotEmpty ? _customerPhoneController.text.trim() : null,
          'payment_status': 'Unpaid',
          'discount_amount': 0.0,
          'order_taker_name': _selectedWaiterName ?? orderTakerName,
          'order_taker_id': _selectedWaiterId ?? orderTakerId,
        });

        for (var item in _cartItems) {
          final note = item.formattedNotes;
          await db.insert('order_items', {
            'order_id': orderId,
            'product_id': item.product.id,
            'quantity': item.quantity,
            'price': item.product.price,
            'status': 'Pending',
            'notes': note.isNotEmpty ? note : null,
          });
        }

        if (_selectedTableId != null) {
          await db.update(
            'tables',
            {'status': 'Occupied'},
            where: 'id = ?',
            whereArgs: [_selectedTableId],
          );
        }
      }

      // Generate KOT Ticket
      await DatabaseHelper.instance.generateKOTForOrder(orderId, _selectedChefName);

      setState(() {
        _cartItems.clear();
        _selectedTableId = null;
        _selectedTableDisplayName = 'Select';
        _customerNameController.clear();
        _customerPhoneController.clear();
        _isTakingOrder = false;
        _selectedChefId = null;
        _selectedChefName = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order successfully sent to kitchen! (Bill #$orderId)')),
      );

      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit order: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- ACTIONS: SERVE, BILL, TRANSFER ---
  Future<void> _markOrderAsServed(int orderId, int? tableId) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      await db.update(
        'kot',
        {
          'status': 'Served',
          'served_at': DateTime.now().toIso8601String(),
        },
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      await db.update(
        'order_items',
        {'status': 'Served'},
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'Waiter';
      final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
      String deliveredByName = username;
      int? deliveredById;
      if (userList.isNotEmpty) {
        deliveredByName = userList.first['name'] as String? ?? username;
        deliveredById = userList.first['id'] as int?;
      }

      await db.update(
        'orders',
        {
          'status': 'Served',
          'delivered_by_name': deliveredByName,
          'delivered_by_id': deliveredById,
          'delivery_timestamp': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (tableId != null) {
        await db.update(
          'tables',
          {'status': 'Served'},
          where: 'id = ?',
          whereArgs: [tableId],
        );
      }

      await DatabaseHelper.instance.logOrderStatus(orderId, 'Served', notes: 'Food successfully served to customer by Waiter.');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order marked as served.')),
      );
      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      debugPrint('Error serving order: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestBilling(int orderId, int? tableId) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      await db.update(
        'orders',
        {'status': 'Billing Pending'},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (tableId != null) {
        await db.update(
          'tables',
          {'status': 'Billing Pending'},
          where: 'id = ?',
          whereArgs: [tableId],
        );
      }

      await DatabaseHelper.instance.logOrderStatus(orderId, 'Billing Pending', notes: 'Waiter requested checkout and billing.');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing request sent to Cashier.')),
      );
      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      debugPrint('Error requesting billing: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showTransferTableDialog(int orderId, int currentTableId, String currentDisplayName) {
    int? targetTableId;

    final availableTables = _tableInfoList
        .where((ti) => ti.table.status == 'Available' && ti.table.id != currentTableId)
        .map((ti) => ti.table)
        .toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Transfer $currentDisplayName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select destination empty table to transfer this active order:'),
              const SizedBox(height: 16),
              if (availableTables.isEmpty)
                const Text('No available empty tables to transfer to.', style: TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Destination Table'),
                  items: availableTables.map((t) {
                    return DropdownMenuItem<int>(
                      value: t.id,
                      child: Text('${t.displayName} • ${t.section} (Cap: ${t.capacity})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      targetTableId = val;
                    });
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: targetTableId == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _executeTableTransfer(orderId, currentTableId, targetTableId!);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              child: const Text('Transfer Order'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeTableTransfer(int orderId, int sourceTableId, int targetTableId) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      await db.transaction((txn) async {
        await txn.update(
          'orders',
          {'table_id': targetTableId},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        await txn.update(
          'tables',
          {'status': 'Occupied'},
          where: 'id = ?',
          whereArgs: [targetTableId],
        );

        await txn.update(
          'tables',
          {'status': 'Available'},
          where: 'id = ?',
          whereArgs: [sourceTableId],
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Table transfer completed successfully.')),
      );
      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- STATUS COLOR HELPERS ---
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Available':
        return const Color(0xFF2E7D32); // Emerald Green
      case 'Occupied':
        return const Color(0xFF1565C0); // Vibrant Blue
      case 'Reserved':
        return const Color(0xFFE65100); // Amber Orange
      case 'Ordering':
        return const Color(0xFF3949AB); // Indigo
      case 'Preparing':
      case 'Sent to Kitchen':
        return const Color(0xFFF57C00); // Bright Orange
      case 'Ready':
        return Colors.purple;
      case 'Served':
        return const Color(0xFF00897B); // Teal
      case 'Billing Pending':
      case 'Bill Requested':
        return const Color(0xFFF9A825); // Gold / Yellow
      case 'Cleaning':
        return const Color(0xFF0288D1); // Cyan Blue
      case 'Out of Service':
        return const Color(0xFF546E7A); // Slate Grey
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getTableTypeIcon(String tableType) {
    switch (tableType) {
      case 'Booth':
        return Icons.weekend_outlined;
      case 'Round Table':
        return Icons.circle_outlined;
      case 'Counter':
      case 'Bar Counter':
        return Icons.wine_bar;
      case 'Outdoor Table':
        return Icons.deck_outlined;
      default:
        return Icons.table_restaurant;
    }
  }

  // --- MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.deepPurple)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiter Order Management', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: _isTakingOrder
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: Colors.deepPurple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.deepPurple,
                tabs: const [
                  Tab(icon: Icon(Icons.grid_view), text: 'Floor Plan (Live Tables)'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'Kitchen Orders'),
                ],
              ),
        actions: [
          // Quick Water & Table Service Action
          ElevatedButton.icon(
            onPressed: () => _showQuickWaterServiceDialog(),
            icon: const Icon(Icons.water_drop, color: Colors.blue, size: 18),
            label: const Text('Quick Water / Service'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              foregroundColor: Colors.blue.shade800,
              elevation: 0,
            ),
          ),
          const SizedBox(width: 8),

          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Floor',
            onPressed: _loadDashboardAndProducts,
          ),
          const SizedBox(width: 8),

          // Order Taking Mode Toggle
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _isTakingOrder = !_isTakingOrder;
                if (!_isTakingOrder) {
                  _cartItems.clear();
                }
              });
            },
            icon: Icon(_isTakingOrder ? Icons.arrow_back : Icons.add_shopping_cart),
            label: Text(_isTakingOrder ? 'Back to Dashboard' : 'Take Customer Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTakingOrder ? Colors.grey.shade700 : Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isTakingOrder
          ? _buildOrderTakingPanel()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFloorPlanTab(),
                _buildKitchenOrdersTab(),
              ],
            ),
    );
  }

  // --- FLOOR PLAN TAB ---
  Widget _buildFloorPlanTab() {
    final filteredTables = _tableInfoList.where((ti) {
      final matchesSection = _selectedSectionFilter == 'All' || ti.table.section == _selectedSectionFilter;
      final matchesStatus = _selectedStatusFilter == 'All' || ti.table.status == _selectedStatusFilter;
      return matchesSection && matchesStatus;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section & Status Filters
          Row(
            children: [
              // Section Filter Chips
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sectionsList.length,
                    itemBuilder: (context, index) {
                      final sec = _sectionsList[index];
                      final isSelected = sec == _selectedSectionFilter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(sec, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected,
                          selectedColor: Colors.deepPurple,
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            setState(() => _selectedSectionFilter = sec);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Status Filter Chips
              DropdownButton<String>(
                value: _selectedStatusFilter,
                underline: const SizedBox(),
                items: ['All', 'Available', 'Occupied', 'Billing Pending', 'Served', 'Cleaning'].map((st) {
                  return DropdownMenuItem<String>(
                    value: st,
                    child: Text('Status: $st', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedStatusFilter = val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Floor Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendChip(const Color(0xFF2E7D32), 'Available'),
              _buildLegendChip(const Color(0xFF1565C0), 'Occupied'),
              _buildLegendChip(const Color(0xFFF9A825), 'Billing Pending'),
              _buildLegendChip(const Color(0xFF00897B), 'Served'),
              _buildLegendChip(const Color(0xFF0288D1), 'Cleaning'),
            ],
          ),
          const SizedBox(height: 16),

          // Tables Grid
          Expanded(
            child: filteredTables.isEmpty
                ? const Center(child: Text('No tables found for this filter.', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: filteredTables.length,
                    itemBuilder: (context, index) {
                      final tableInfo = filteredTables[index];
                      final table = tableInfo.table;
                      final activeOrder = tableInfo.activeOrder;
                      final statusColor = _getStatusColor(table.status);
                      final typeIcon = _getTableTypeIcon(table.tableType);

                      return Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1.5),
                        ),
                        color: statusColor.withValues(alpha: 0.03),
                        child: InkWell(
                          onTap: () => _handleTableCardTap(tableInfo),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Table Type Icon & Status Badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: statusColor.withValues(alpha: 0.15),
                                      child: Icon(typeIcon, color: statusColor, size: 16),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        table.status.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),

                                // Display Name
                                Text(
                                  table.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),

                                // Section & Capacity
                                Text(
                                  '${table.section} • ${table.capacity} Seats',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),

                                // Active Order summary if present
                                if (activeOrder != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurple.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Order #${activeOrder['id']} • ₹${activeOrder['total_amount']}',
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                                    ),
                                  ),
                                ],
                                const Spacer(),

                                // Quick Action Bar on each card
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Quick Water Action Button
                                    InkWell(
                                      onTap: () => _showQuickWaterServiceDialog(preselectedTable: table),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.water_drop, size: 12, color: Colors.blue),
                                            SizedBox(width: 4),
                                            Text('Water', style: TextStyle(fontSize: 10.5, color: Colors.blue, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Take Order / View Order Button
                                    ElevatedButton(
                                      onPressed: () => _handleTableCardTap(tableInfo),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: statusColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        activeOrder != null ? 'View' : 'Order',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
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
        ],
      ),
    );
  }

  Widget _buildLegendChip(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _handleTableCardTap(_WaiterTableInfo tableInfo) {
    final table = tableInfo.table;
    final activeOrder = tableInfo.activeOrder;

    if (activeOrder == null) {
      // Table is empty or available -> Start new order directly
      setState(() {
        _selectedTableId = table.id;
        _selectedTableDisplayName = table.displayName;
        _orderType = 'Dine-In';
        _isTakingOrder = true;
        _cartItems.clear();
      });
      return;
    }

    // Active order exists: Show Action Bottom Sheet
    final orderId = activeOrder['id'] as int;
    final waiterName = activeOrder['order_taker_name'] as String? ?? 'N/A';
    final customerName = activeOrder['customer_name'] as String? ?? 'Guest';
    final orderStatus = activeOrder['status'] as String? ?? 'Received';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      table.displayName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(table.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Status: ${table.status}',
                        style: TextStyle(color: _getStatusColor(table.status), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.deepPurple),
                  title: Text('Active Order #$orderId (${activeOrder['type'] ?? "Dine-In"})'),
                  subtitle: Text('Guest: $customerName • Waiter: $waiterName • Items: ${tableInfo.orderItemsCount}'),
                  dense: true,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart, size: 16),
                      label: const Text('Add Items'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedTableId = table.id;
                          _selectedTableDisplayName = table.displayName;
                          _orderType = 'Dine-In';
                          _isTakingOrder = true;
                          _cartItems.clear();
                        });
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.water_drop, size: 16),
                      label: const Text('Quick Water'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        _showQuickWaterServiceDialog(preselectedTable: table);
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.move_down, size: 16),
                      label: const Text('Transfer'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        _showTransferTableDialog(orderId, table.id!, table.displayName);
                      },
                    ),
                    if (orderStatus != 'Billing Pending')
                      ElevatedButton.icon(
                        icon: const Icon(Icons.request_page_outlined, size: 16),
                        label: const Text('Bill Request'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                        onPressed: () {
                          Navigator.pop(context);
                          _requestBilling(orderId, table.id);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- KITCHEN ORDERS TAB ---
  Widget _buildKitchenOrdersTab() {
    final activeOrdersCount = _waiterOrdersList.length;
    final readyCount = _waiterOrdersList.where((o) => o['status'] == 'Ready').length;
    final servedCount = _waiterOrdersList.where((o) => o['status'] == 'Served').length;
    final billingCount = _waiterOrdersList.where((o) => o['status'] == 'Billing Pending').length;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatsChip(Icons.circle, Colors.blue, 'Active: $activeOrdersCount'),
              _buildStatsChip(Icons.restaurant_menu, Colors.purple, 'Ready: $readyCount'),
              _buildStatsChip(Icons.check_circle, const Color(0xFF00897B), 'Served: $servedCount'),
              _buildStatsChip(Icons.request_quote, Colors.orange, 'Billing: $billingCount'),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Live Kitchen Orders Tracking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Expanded(
            child: _waiterOrdersList.isEmpty
                ? const Center(
                    child: Text('No active kitchen orders taken.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  )
                : ListView.builder(
                    itemCount: _waiterOrdersList.length,
                    itemBuilder: (context, index) {
                      final order = _waiterOrdersList[index];
                      final orderId = order['id'] as int;
                      final tableNum = order['table_number'] as String? ?? 'Takeaway';
                      final tableName = order['table_name'] as String?;
                      final tableDisplay = tableName != null && tableName.isNotEmpty ? 'T-$tableNum ($tableName)' : 'Table $tableNum';
                      final customer = order['customer_name'] as String? ?? 'N/A';
                      final total = order['total_amount'] as num? ?? 0.0;
                      final type = order['type'] as String? ?? 'Dine-In';
                      final status = order['status'] as String? ?? 'Received';
                      final orderTime = order['order_time'] as String? ?? '';
                      final parsedTime = DateTime.tryParse(orderTime) ?? DateTime.now();

                      final statusColor = _getStatusColor(status);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: statusColor.withValues(alpha: 0.12),
                                radius: 26,
                                child: Text(tableNum, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          tableDisplay,
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Customer: $customer • Type: $type • Time: ${DateFormat('hh:mm a').format(parsedTime)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                    Text('Total: ₹${total.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                                  ],
                                ),
                              ),
                              // Waiter Action Options
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (status == 'Ready')
                                    ElevatedButton.icon(
                                      onPressed: () => _markOrderAsServed(orderId, order['table_id'] as int?),
                                      icon: const Icon(Icons.check, size: 14),
                                      label: const Text('Mark Served'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00897B),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  if (status == 'Served')
                                    ElevatedButton.icon(
                                      onPressed: () => _requestBilling(orderId, order['table_id'] as int?),
                                      icon: const Icon(Icons.request_page_outlined, size: 14),
                                      label: const Text('Request Bill'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  if (type == 'Dine-In' && status != 'Billing Pending' && status != 'Served')
                                    IconButton(
                                      icon: const Icon(Icons.move_down, color: Colors.blue),
                                      tooltip: 'Transfer Table',
                                      onPressed: () => _showTransferTableDialog(orderId, order['table_id'] as int, tableDisplay),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsChip(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // --- ORDER TAKING PANEL ---
  Widget _buildOrderTakingPanel() {
    final filteredProducts = _products.where((p) {
      final matchesCat = _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();

    return Row(
      children: [
        // Left Side: Catalog of products with preferences & attributes
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search Field
                TextField(
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
                const SizedBox(height: 12),

                // Category Tabs Selector
                SizedBox(
                  height: 42,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = cat == _selectedCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(cat, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 12)),
                          selected: isSelected,
                          selectedColor: Colors.deepPurple,
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            setState(() => _selectedCategory = cat);
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Product Grid View
                Expanded(
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
                      final inCartCount = _cartItems.where((it) => it.product.id == prod.id).fold(0, (sum, it) => sum + it.quantity);

                      return Card(
                        color: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: InkWell(
                          onTap: () => _handleProductTap(prod),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
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
                                      CircleAvatar(
                                        backgroundColor: Colors.deepPurple,
                                        radius: 10,
                                        child: Text('$inCartCount', style: const TextStyle(color: Colors.white, fontSize: 10)),
                                      ),
                                  ],
                                ),
                                const Spacer(),

                                // Name
                                Text(
                                  prod.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),

                                // Food Attributes Badge (compact micro tags)
                                if (prod.hasAttributes || prod.hasPreferences) ...[
                                  const SizedBox(height: 4),
                                  FoodAttributesBadge(product: prod, compact: true, maxVisible: 2),
                                ],

                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('₹${prod.price}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                    Icon(
                                      prod.hasPreferences ? Icons.tune : Icons.add_circle,
                                      color: Colors.deepPurple,
                                      size: 20,
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
              ],
            ),
          ),
        ),

        // Right Side: Cart side panel with dynamic preference chips
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey.shade200)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Order Setup Header
                Text(
                  _orderType == 'Dine-In' ? 'Order: $_selectedTableDisplayName' : 'New Order - Takeaway',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),

                // Order Type & Table Selection
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _orderType,
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Type', isDense: true),
                        items: ['Dine-In', 'Takeaway', 'Delivery'].map((type) {
                          return DropdownMenuItem<String>(value: type, child: Text(type));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _orderType = val!;
                            if (_orderType != 'Dine-In') {
                              _selectedTableId = null;
                              _selectedTableDisplayName = 'Takeaway';
                            }
                          });
                        },
                      ),
                    ),
                    if (_orderType == 'Dine-In') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: SearchableDropdown<_WaiterTableInfo>(
                          items: _tableInfoList,
                          value: _selectedTableId != null && _tableInfoList.any((ti) => ti.table.id == _selectedTableId)
                              ? _tableInfoList.firstWhere((ti) => ti.table.id == _selectedTableId)
                              : null,
                          labelText: 'Table',
                          hintText: 'Select...',
                          itemToString: (ti) => '${ti.table.displayName} (${ti.table.status})',
                          filterFn: (ti, query) => ti.table.displayName.toLowerCase().contains(query.toLowerCase()),
                          onChanged: (val) {
                            setState(() {
                              _selectedTableId = val?.table.id;
                              _selectedTableDisplayName = val != null ? val.table.displayName : 'Takeaway';
                            });
                          },
                          prefixIcon: const Icon(Icons.table_restaurant),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Customer Info
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customerNameController,
                        decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customerPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Waiter & Chef assignment
                Row(
                  children: [
                    Expanded(
                      child: SearchableDropdown<Map<String, dynamic>>(
                        items: _waitersList,
                        value: _selectedWaiterId != null && _waitersList.any((w) => w['id'] == _selectedWaiterId)
                            ? _waitersList.firstWhere((w) => w['id'] == _selectedWaiterId)
                            : null,
                        labelText: 'Waiter',
                        hintText: 'Select...',
                        itemToString: (w) => w['name'] as String? ?? '',
                        filterFn: (w, query) => (w['name'] as String? ?? '').toLowerCase().contains(query.toLowerCase()),
                        onChanged: (val) {
                          setState(() {
                            _selectedWaiterId = val?['id'] as int?;
                            _selectedWaiterName = val?['name'] as String?;
                          });
                        },
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SearchableDropdown<Map<String, dynamic>>(
                        items: _chefsList,
                        value: _selectedChefId != null && _chefsList.any((c) => c['id'] == _selectedChefId)
                            ? _chefsList.firstWhere((c) => c['id'] == _selectedChefId)
                            : null,
                        labelText: 'Chef',
                        hintText: 'Select...',
                        itemToString: (c) => c['name'] as String? ?? '',
                        filterFn: (c, query) => (c['name'] as String? ?? '').toLowerCase().contains(query.toLowerCase()),
                        onChanged: (val) {
                          setState(() {
                            _selectedChefId = val?['id'] as int?;
                            _selectedChefName = val?['name'] as String?;
                          });
                        },
                        prefixIcon: const Icon(Icons.restaurant_menu),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),

                // Selected Items Cart List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Selected Items List', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_cartItems.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _cartItems.clear()),
                        child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),

                // Selected Items Cart List
                Expanded(
                  child: _cartItems.isEmpty
                      ? const Center(child: Text('No items added. Click on menu cards to append.'))
                      : ListView.builder(
                          itemCount: _cartItems.length,
                          itemBuilder: (context, index) {
                            final item = _cartItems[index];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.product.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                                              onPressed: () => _decrementCart(index),
                                            ),
                                            Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 18),
                                              onPressed: () => setState(() => item.quantity++),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                              onPressed: () => _removeCartItem(index),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    // Customization & Preference Badges
                                    if (item.dietaryPreference != null || item.tastePreference != null || (item.notes != null && item.notes!.isNotEmpty)) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (item.dietaryPreference != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.green.shade300),
                                              ),
                                              child: Text(
                                                item.dietaryPreference!,
                                                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          if (item.tastePreference != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.deepOrange.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.deepOrange.shade300),
                                              ),
                                              child: Text(
                                                item.tastePreference!,
                                                style: TextStyle(fontSize: 10, color: Colors.deepOrange.shade800, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          if (item.notes != null && item.notes!.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                item.notes!,
                                                style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],

                                    const SizedBox(height: 4),
                                    Text(
                                      '₹${item.subtotal.toStringAsFixed(2)}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepPurple),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(),

                // Totals & Submit
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total (excluding Tax):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('₹${_calculateSubtotal().toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _submitWaiterOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Send Order to Kitchen (KOT)', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
