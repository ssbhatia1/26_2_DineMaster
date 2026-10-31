import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:dine_master/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../core/database/network_database.dart';
import '../models/product_model.dart';
import '../models/table_model.dart';
import '../repositories/product_repository.dart';
import '../services/sync_service.dart';
import 'waiter/waiter_models.dart';
import 'waiter/components/waiter_cart_panel.dart';
import 'waiter/components/waiter_menu_view.dart';
import 'waiter/components/waiter_floor_plan_view.dart';
import 'waiter/components/item_customization_dialog.dart';
import '../services/backend_api_client.dart';

class WaiterOrderScreen extends StatefulWidget {
  final int? selectedTableId;
  const WaiterOrderScreen({super.key, this.selectedTableId});

  @override
  State<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

class _WaiterOrderScreenState extends State<WaiterOrderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductRepository _productRepository = ProductRepository();

  bool _isLoading = true;
  bool _isTakingOrder = false;

  // Floor Plan States
  List<WaiterTableInfo> _tableInfoList = [];
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
  int? _currentOrderGuestCount;
  final TextEditingController _customerNameController = TextEditingController(
    text: 'Walking Customer',
  );
  final TextEditingController _customerPhoneController =
      TextEditingController();

  bool _showWaiterAssignment = true;
  bool _showChefAssignment = true;

  // Cart list
  final List<WaiterCartItem> _cartItems = [];

  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.selectedTableId != null) {
      _selectedTableId = widget.selectedTableId;
      _isTakingOrder = true;
    }
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
      final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;

      // 1. Fetch tables and active orders
      final List<Map<String, dynamic>> tablesResult = await db.query(
        'tables',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );

      final List<WaiterTableInfo> enrichedTables = [];
      final Set<String> sections = {'All'};

      for (var tMap in tablesResult) {
        final table = TableModel.fromMap(tMap);
        if (table.section.isNotEmpty) {
          sections.add(table.section);
        }

        // Check active order (unpaid and active)
        final List<Map<String, dynamic>> activeOrders = await db.query(
          'orders',
          where:
              'table_id = ? AND status IN (\'Received\', \'Sent to Kitchen\', \'In Kitchen\', \'Preparing\', \'Ready\', \'Served\', \'Billing Pending\', \'Held\') AND payment_status != ? AND (restaurant_id = ? OR restaurant_id IS NULL)',
          whereArgs: [table.id, 'Paid', restaurantId],
          orderBy: 'id DESC',
          limit: 1,
        );

        Map<String, dynamic>? activeOrder = activeOrders.isNotEmpty
            ? activeOrders.first
            : null;
        int itemsCount = 0;

        if (activeOrder != null) {
          final items = await db.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [activeOrder['id']],
          );
          itemsCount = items.fold(
            0,
            (sum, it) => sum + (it['quantity'] as int? ?? 1),
          );
        }

        // Check active booking (reservation active within current hour window)
        final now = DateTime.now();
        final List<Map<String, dynamic>> bookingMaps = await db.query(
          'bookings',
          where:
              'table_id = ? AND status = ? AND (restaurant_id = ? OR restaurant_id IS NULL)',
          whereArgs: [table.id, 'Confirmed', restaurantId],
        );

        Map<String, dynamic>? currentBooking;
        for (final b in bookingMaps) {
          final bTimeStr = b['booking_time'] as String?;
          if (bTimeStr == null) continue;
          final bTime = DateTime.tryParse(bTimeStr);
          if (bTime == null) continue;
          final slotEnd = bTime.add(const Duration(hours: 1));
          if (!now.isBefore(bTime) && now.isBefore(slotEnd)) {
            currentBooking = b;
            break;
          }
        }

        // Keep status as Occupied if order or booking is active
        TableModel displayTable = table;
        if ((activeOrder != null || currentBooking != null) &&
            table.status == 'Available') {
          await db.update(
            'tables',
            {'status': 'Occupied'},
            where: 'id = ?',
            whereArgs: [table.id],
          );
          displayTable = table.copyWith(status: 'Occupied');
        }

        enrichedTables.add(
          WaiterTableInfo(
            table: displayTable,
            activeOrder: activeOrder,
            activeBooking: currentBooking,
            orderItemsCount: itemsCount,
          ),
        );
      }

      _tableInfoList = enrichedTables;
      _sectionsList = sections.toList();

      // Attach merged member tables so merged groups render as a single entity.
      for (final ti in _tableInfoList) {
        ti.mergedTables = tablesResult
            .where((m) => m['merged_with_id'] == ti.table.id)
            .map((m) => TableModel.fromMap(m))
            .toList();
      }

      if (_selectedTableId != null) {
        final tableInfo = _tableInfoList.firstWhere(
          (t) => t.table.id == _selectedTableId,
          orElse: () => _tableInfoList.first,
        );
        _selectedTableDisplayName = tableInfo.displayNameForOrder;
      }

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
      final List<Map<String, dynamic>> ordersResult = await db.rawQuery(
        '''
        SELECT o.*, t.table_number, t.name as table_name, t.section as table_section
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.status IN ('Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served', 'Billing Pending', 'Confirmed', 'Held')
        AND o.restaurant_id = ?
        ORDER BY o.id DESC
      ''',
        [restaurantId],
      );
      _waiterOrdersList = List<Map<String, dynamic>>.from(ordersResult);

      final prefs = await SharedPreferences.getInstance();
      _showWaiterAssignment = prefs.getBool('show_waiter_assignment') ?? true;
      _showChefAssignment = prefs.getBool('show_chef_assignment') ?? true;

      // 4. Fetch active chefs and waiters
      List<Map<String, dynamic>> allUsers = [];

      if (kIsWeb || db is NetworkDatabase) {
        final response = await const BackendApiClient().getJson('/api/users');

        if (response is List) {
          allUsers = response
              .whereType<Map>()
              .map((user) => Map<String, dynamic>.from(user))
              .where((user) {
                final active = user['active'] ?? user['is_active'];
                return active == true || active == 1;
              })
              .toList();
        }
      } else {
        final usersResult = await db.query(
          'users',
          where: 'is_active = ?',
          whereArgs: [1],
        );

        allUsers = List<Map<String, dynamic>>.from(usersResult);
      }

      _chefsList = allUsers.where((user) {
        final role = user['role']?.toString().trim().toUpperCase();
        return role == 'CHEF' || role == 'COOK';
      }).toList();

      _waitersList = allUsers.where((user) {
        final role = user['role']?.toString().trim().toUpperCase();
        return role == 'WAITER';
      }).toList();

      // Auto-select logged-in waiter
      final username = prefs.getString('username');

      if (username != null && _selectedWaiterId == null) {
        final matchedWaiters = _waitersList.where(
          (w) => w['username']?.toString() == username,
        );

        if (matchedWaiters.isNotEmpty) {
          _selectedWaiterId = (matchedWaiters.first['id'] as num?)?.toInt();
          _selectedWaiterName = matchedWaiters.first['name']?.toString();
        }
      }

      debugPrint('Loaded ${_waitersList.length} waiters');
      debugPrint('Loaded ${_chefsList.length} chefs');

      // --- CART MANAGEMENT ---
    } catch (e, stackTrace) {
      debugPrint('Error loading waiter configurations: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleProductTap(ProductModel product) async {
    if (product.hasPreferences) {
      final res = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ItemCustomizationDialog(product: product),
      );

      if (res != null) {
        _addToCart(
          product,
          dietaryPreference: res['dietaryPreference'],
          tastePreference: res['tastePreference'],
          notes: res['notes'],
          qty: res['quantity'] ?? 1,
        );
      }
    } else {
      _addToCart(product, qty: 1);
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
        _cartItems.add(
          WaiterCartItem(
            product: product,
            quantity: qty,
            dietaryPreference: dietaryPreference,
            tastePreference: tastePreference,
            notes: notes,
          ),
        );
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

  void _editCartItem(int index) {
    if (index >= 0 && index < _cartItems.length) {
      final item = _cartItems[index];
      _showPreferenceCustomizationDialog(
        item.product,
        existingItem: item,
        existingIndex: index,
      );
    }
  }

  double _calculateSubtotal() {
    return _cartItems.fold(0.0, (sum, it) => sum + it.subtotal);
  }

  /// Calculates GST using each product's individual gst_percentage field.
  double _calculateTax() {
    return _cartItems.fold(0.0, (sum, it) {
      final gst = (it.product.gstPercentage > 0) ? it.product.gstPercentage : 5.0;
      return sum + (it.subtotal * gst / 100);
    });
  }

  // --- ITEM CUSTOMIZATION DIALOG ---
  void _showPreferenceCustomizationDialog(
    ProductModel product, {
    WaiterCartItem? existingItem,
    int? existingIndex,
  }) {
    String? selectedDietary = existingItem?.dietaryPreference;
    String? selectedTaste = existingItem?.tastePreference;
    int quantity = existingItem?.quantity ?? 1;
    final notesCtrl = TextEditingController(text: existingItem?.notes ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.tune, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
                  const Text(
                    'Dietary Preference',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Regular'),
                        selected: selectedDietary == null,
                        onSelected: (val) =>
                            setDlgState(() => selectedDietary = null),
                      ),
                      ...product.dietaryPreferences.map((pref) {
                        return ChoiceChip(
                          label: Text(pref),
                          selected: selectedDietary == pref,
                          selectedColor: Colors.green.shade100,
                          onSelected: (val) => setDlgState(
                            () => selectedDietary = val ? pref : null,
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Taste Profile (Filtered to only what is configured for this dish)
                if (product.tastePreferences.isNotEmpty) ...[
                  const Text(
                    'Taste Profile',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Default'),
                        selected: selectedTaste == null,
                        onSelected: (val) =>
                            setDlgState(() => selectedTaste = null),
                      ),
                      ...product.tastePreferences.map((taste) {
                        return ChoiceChip(
                          label: Text(taste),
                          selected: selectedTaste == taste,
                          selectedColor: Colors.deepOrange.shade100,
                          onSelected: (val) => setDlgState(
                            () => selectedTaste = val ? taste : null,
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Custom Dietary Notes from Admin
                if (product.customDietaryNotes != null &&
                    product.customDietaryNotes!.trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.purple,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            product.customDietaryNotes!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.purple,
                            ),
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
                    const Text(
                      'Quantity:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: quantity > 1
                              ? () => setDlgState(() => quantity--)
                              : null,
                        ),
                        Text(
                          '$quantity',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
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
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                if (existingItem != null && existingIndex != null) {
                  setState(() {
                    _cartItems[existingIndex].dietaryPreference =
                        selectedDietary;
                    _cartItems[existingIndex].tastePreference = selectedTaste;
                    _cartItems[existingIndex].notes =
                        notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null;
                    _cartItems[existingIndex].quantity = quantity;
                  });
                } else {
                  _addToCart(
                    product,
                    dietaryPreference: selectedDietary,
                    tastePreference: selectedTaste,
                    notes: notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null,
                    qty: quantity,
                  );
                }
              },
              child: Text(
                existingItem != null ? 'Update Order' : 'Add to Order',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SUBMIT WAITER ORDER (KOT) ---
  Future<void> _submitWaiterOrder() async {
    if (_cartItems.isEmpty) return;

    if (_orderType == 'Dine-In' && _selectedTableId == null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;
      final String now = DateTime.now().toIso8601String();

      // All order-related database operations use the same executor.
      Future<int> persistOrder(DatabaseExecutor executor) async {
        int orderId;

        List<Map<String, Object?>> existingOrder = [];

        // Check whether the table already has an active order.
        if (_orderType == 'Dine-In' && _selectedTableId != null) {
          existingOrder = await executor.query(
            'orders',
            where:
                "table_id = ? AND status IN "
                "('Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served') "
                "AND restaurant_id = ?",
            whereArgs: [_selectedTableId, restaurantId],
          );
        }

        if (existingOrder.isNotEmpty) {
          // Append items to the existing order.
          orderId = (existingOrder.first['id'] as num).toInt();

          for (final item in _cartItems) {
            final note = item.formattedNotes;

            await executor.insert('order_items', {
              'order_id': orderId,
              'product_id': item.product.id,
              'quantity': item.quantity,
              'price': item.product.price,
              'status': 'Pending',
              'notes': note.isNotEmpty ? note : null,
            });
          }

          final double subtotal = _calculateSubtotal();

          final double prevTotal = (existingOrder.first['total_amount'] as num)
              .toDouble();

          final double tax = _calculateTax();
          final double newTotal = prevTotal + subtotal + tax;

          await executor.update(
            'orders',
            {'total_amount': newTotal},
            where: 'id = ?',
            whereArgs: [orderId],
          );
        } else {
          // Create a new order.
          final double subtotal = _calculateSubtotal();
          final double tax = _calculateTax();
          final double total = subtotal + tax;

          final prefs = await SharedPreferences.getInstance();
          final username = prefs.getString('username') ?? 'Waiter';

          final userList = await executor.query(
            'users',
            where: 'username = ?',
            whereArgs: [username],
          );

          String orderTakerName = username;
          int? orderTakerId;

          if (userList.isNotEmpty) {
            orderTakerName = userList.first['name'] as String? ?? username;

            final userId = userList.first['id'];
            orderTakerId = userId is num ? userId.toInt() : null;
          }

          orderId = await executor.insert('orders', {
            'total_amount': total,
            'status': 'Sent to Kitchen',
            'type': _orderType,
            'order_time': now,
            'restaurant_id': restaurantId,
            'table_id': _selectedTableId,
            'customer_name': _customerNameController.text.trim().isNotEmpty
                ? _customerNameController.text.trim()
                : 'Guest',
            'customer_phone': _customerPhoneController.text.trim().isNotEmpty
                ? _customerPhoneController.text.trim()
                : null,
            'payment_status': 'Unpaid',
            'discount_amount': 0.0,
            'order_taker_name': _selectedWaiterName ?? orderTakerName,
            'order_taker_id': _selectedWaiterId ?? orderTakerId,
            'guest_count': _currentOrderGuestCount,
          });

          // Insert order items.
          for (final item in _cartItems) {
            final note = item.formattedNotes;

            await executor.insert('order_items', {
              'order_id': orderId,
              'product_id': item.product.id,
              'quantity': item.quantity,
              'price': item.product.price,
              'status': 'Pending',
              'notes': note.isNotEmpty ? note : null,
            });
          }

          // Mark merged table group as occupied.
          if (_selectedTableId != null) {
            final groupIds = <int>[_selectedTableId!];

            groupIds.addAll(
              _tableInfoList
                  .where((t) => t.table.mergedWithId == _selectedTableId)
                  .map((t) => t.table.id!),
            );

            await executor.update(
              'tables',
              {'status': 'Occupied'},
              where: 'id IN (${groupIds.map((_) => '?').join(', ')})',
              whereArgs: groupIds,
            );
          }
        }

        // Generate KOT using the same database executor.
        await DatabaseHelper.instance.generateKOTForOrder(
          orderId,
          _selectedChefName,
          executor,
        );

        return orderId;
      }

      // NetworkDatabase does not provide real transaction semantics.
      // Preserve sequential execution for network-backed databases.
      if (db is NetworkDatabase) {
        await persistOrder(db);
      } else {
        // Native SQLite: order, items, table status and KOT
        // are committed together or rolled back together.
        await db.transaction<int>((txn) async {
          return await persistOrder(txn);
        });
      }

      if (!mounted) return;

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

      _loadDashboardAndProducts();

      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e, stackTrace) {
      debugPrint('Waiter order submission failed: $e');
      debugPrintStack(stackTrace: stackTrace);
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
        {'status': 'Served', 'served_at': DateTime.now().toIso8601String()},
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
      final userList = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );
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
          // Food served: table stays 'Occupied' until billing completes.
          {'status': 'Occupied'},
          where: 'id = ?',
          whereArgs: [tableId],
        );
      }

      await DatabaseHelper.instance.logOrderStatus(
        orderId,
        'Served',
        notes: 'Food successfully served to customer by Waiter.',
      );

      if (!mounted) return;

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

      await DatabaseHelper.instance.logOrderStatus(
        orderId,
        'Billing Pending',
        notes: 'Waiter requested checkout and billing.',
      );

      if (!mounted) return;

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

  void _showTransferTableDialog(
    int orderId,
    int currentTableId,
    String currentDisplayName,
  ) {
    int? targetTableId;

    final availableTables = _tableInfoList
        .where(
          (ti) =>
              ti.table.status == 'Available' && ti.table.id != currentTableId,
        )
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
              const Text(
                'Select destination empty table to transfer this active order:',
              ),
              const SizedBox(height: 16),
              if (availableTables.isEmpty)
                const Text(
                  'No available empty tables to transfer to.',
                  style: TextStyle(color: Colors.red),
                )
              else
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Destination Table',
                  ),
                  items: availableTables.map((t) {
                    return DropdownMenuItem<int>(
                      value: t.id,
                      child: Text(
                        '${t.displayName} • ${t.section} (Cap: ${t.capacity})',
                      ),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: targetTableId == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _executeTableTransfer(
                        orderId,
                        currentTableId,
                        targetTableId!,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Transfer Order'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeTableTransfer(
    int orderId,
    int sourceTableId,
    int targetTableId,
  ) async {
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

      _loadDashboardAndProducts();
      SyncService.instance.broadcastEvent('database_update', {});
    } catch (e) {
      if (!mounted) return;
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

  // --- MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Take Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _isTakingOrder
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primary,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.grid_view),
                    text: 'Floor Plan (Live Tables)',
                  ),
                  Tab(icon: Icon(Icons.receipt_long), text: 'Kitchen Orders'),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            // tooltip disabled,
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
            icon: Icon(
              _isTakingOrder ? Icons.arrow_back : Icons.add_shopping_cart,
            ),
            label: Text(
              _isTakingOrder ? 'Back to Dashboard' : 'Take Customer Order',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTakingOrder
                  ? Colors.grey.shade700
                  : AppColors.primary,
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
              children: [_buildFloorPlanTab(), _buildKitchenOrdersTab()],
            ),
    );
  }

  // --- FLOOR PLAN TAB ---
  Widget _buildFloorPlanTab() {
    return WaiterFloorPlanView(
      tableInfoList: _tableInfoList,
      sectionsList: _sectionsList,
      selectedSectionFilter: _selectedSectionFilter,
      selectedStatusFilter: _selectedStatusFilter,
      onSectionFilterChanged: (val) =>
          setState(() => _selectedSectionFilter = val),
      onStatusFilterChanged: (val) =>
          setState(() => _selectedStatusFilter = val),
      onTableCardTap: _handleTableCardTap,
    );
  }

  Future<void> _promptGuestCountAndTakeOrder(TableModel table) async {
    final tableInfo = _tableInfoList.firstWhere(
      (t) => t.table.id == table.id,
      orElse: () => _tableInfoList.first,
    );
    setState(() {
      _selectedTableId = table.id;
      _selectedTableDisplayName = tableInfo.displayNameForOrder;
      _orderType = 'Dine-In';
      _isTakingOrder = true;
      _cartItems.clear();
      _currentOrderGuestCount = tableInfo.combinedCapacity;
    });
  }

  Future<void> _showMergeTableDialog(TableModel primaryTable) async {
    final availableTables = _tableInfoList
        .where(
          (t) =>
              t.table.id != primaryTable.id &&
              t.table.mergedWithId == null &&
              t.table.status == 'Available',
        )
        .toList();

    if (availableTables.isEmpty) {
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Merge into ${primaryTable.displayName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableTables.length,
            itemBuilder: (context, index) {
              final tableToMerge = availableTables[index].table;
              return ListTile(
                title: Text(tableToMerge.displayName),
                subtitle: Text('Capacity: ${tableToMerge.capacity}'),
                onTap: () async {
                  Navigator.pop(context);
                  final db = await DatabaseHelper.instance.database;
                  await db.update(
                    'tables',
                    {'merged_with_id': primaryTable.id},
                    where: 'id = ?',
                    whereArgs: [tableToMerge.id],
                  );
                  _loadDashboardAndProducts();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _unmergeTable(TableModel table) async {
    final db = await DatabaseHelper.instance.database;

    // Unmerge the whole group: if this is the anchor, clear all its members.
    final List<int> targetIds = [];
    if (table.mergedWithId != null) {
      targetIds.add(table.id!);
    } else {
      targetIds.addAll(
        _tableInfoList
            .where((t) => t.table.mergedWithId == table.id)
            .map((t) => t.table.id!),
      );
    }

    for (final tid in targetIds) {
      await db.update(
        'tables',
        {'merged_with_id': null},
        where: 'id = ?',
        whereArgs: [tid],
      );
    }
    _loadDashboardAndProducts();
  }

  void _handleTableCardTap(WaiterTableInfo tableInfo) {
    final table = tableInfo.table;
    final activeOrder = tableInfo.activeOrder;

    if (activeOrder == null) {
      final isMergedGroup = tableInfo.isMergedGroup;
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMergedGroup)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.merge_type, color: Colors.blue),
                    title: Text(
                      'Merged group: ${tableInfo.mergedTableNumbers} • Capacity: ${tableInfo.combinedCapacity}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.add_shopping_cart,
                    color: AppColors.primary,
                  ),
                  title: const Text('Take Order'),
                  onTap: () {
                    Navigator.pop(context);
                    _promptGuestCountAndTakeOrder(table);
                  },
                ),
                if (isMergedGroup)
                  ListTile(
                    leading: const Icon(Icons.call_split, color: Colors.red),
                    title: Text(
                      'Unmerge merged tables (${tableInfo.mergedTableNumbers})',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _unmergeTable(table);
                    },
                  )
                else if (table.mergedWithId == null)
                  ListTile(
                    leading: const Icon(Icons.merge_type, color: Colors.blue),
                    title: const Text('Merge with another table'),
                    onTap: () {
                      Navigator.pop(context);
                      _showMergeTableDialog(table);
                    },
                  ),
                if (table.mergedWithId != null && !isMergedGroup)
                  ListTile(
                    leading: const Icon(Icons.call_split, color: Colors.red),
                    title: const Text('Unmerge Table'),
                    onTap: () {
                      Navigator.pop(context);
                      _unmergeTable(table);
                    },
                  ),
              ],
            ),
          );
        },
      );
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
                      tableInfo.displayNameForOrder,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          table.status,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Status: ${table.status}',
                        style: TextStyle(
                          color: _getStatusColor(table.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(
                    Icons.receipt_long,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    'Active Order #$orderId (${activeOrder['type'] ?? "Dine-In"})',
                  ),
                  subtitle: Text(
                    'Guest: $customerName • Waiter: $waiterName • Items: ${tableInfo.orderItemsCount}',
                  ),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedTableId = table.id;
                          _selectedTableDisplayName =
                              tableInfo.displayNameForOrder;
                          _orderType = 'Dine-In';
                          _isTakingOrder = true;
                          _cartItems.clear();
                        });
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.move_down, size: 16),
                      label: const Text('Transfer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showTransferTableDialog(
                          orderId,
                          table.id!,
                          table.displayName,
                        );
                      },
                    ),
                    if (orderStatus != 'Billing Pending')
                      ElevatedButton.icon(
                        icon: const Icon(Icons.request_page_outlined, size: 16),
                        label: const Text('Bill Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                        ),
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
    final readyCount = _waiterOrdersList
        .where((o) => o['status'] == 'Ready')
        .length;
    final servedCount = _waiterOrdersList
        .where((o) => o['status'] == 'Served')
        .length;
    final billingCount = _waiterOrdersList
        .where((o) => o['status'] == 'Billing Pending')
        .length;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatsChip(
                Icons.circle,
                Colors.blue,
                'Active: $activeOrdersCount',
              ),
              _buildStatsChip(
                Icons.restaurant_menu,
                Colors.purple,
                'Ready: $readyCount',
              ),
              _buildStatsChip(
                Icons.check_circle,
                const Color(0xFF00897B),
                'Served: $servedCount',
              ),
              _buildStatsChip(
                Icons.request_quote,
                Colors.orange,
                'Billing: $billingCount',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Live Kitchen Orders Tracking',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _waiterOrdersList.isEmpty
                ? const Center(
                    child: Text(
                      'No active kitchen orders taken.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: _waiterOrdersList.length,
                    itemBuilder: (context, index) {
                      final order = _waiterOrdersList[index];
                      final orderId = order['id'] as int;
                      final tableNum =
                          order['table_number'] as String? ?? 'Takeaway';
                      final tableName = order['table_name'] as String?;
                      final tableDisplay =
                          tableName != null && tableName.isNotEmpty
                          ? 'T-$tableNum ($tableName)'
                          : 'Table $tableNum';
                      final customer =
                          order['customer_name'] as String? ?? 'N/A';
                      final total = order['total_amount'] as num? ?? 0.0;
                      final type = order['type'] as String? ?? 'Dine-In';
                      final status = order['status'] as String? ?? 'Received';
                      final orderTime = order['order_time'] as String? ?? '';
                      final parsedTime =
                          DateTime.tryParse(orderTime) ?? DateTime.now();

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
                                backgroundColor: statusColor.withValues(
                                  alpha: 0.12,
                                ),
                                radius: 26,
                                child: Text(
                                  tableNum,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Order #$orderId',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          tableDisplay,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Customer: $customer • Type: $type • Time: ${DateFormat('hh:mm a').format(parsedTime)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Total: ₹${total.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Waiter Action Options
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (status == 'Ready')
                                    ElevatedButton.icon(
                                      onPressed: () => _markOrderAsServed(
                                        orderId,
                                        order['table_id'] as int?,
                                      ),
                                      icon: const Icon(Icons.check, size: 14),
                                      label: const Text('Mark Served'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF00897B,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  if (status == 'Served')
                                    ElevatedButton.icon(
                                      onPressed: () => _requestBilling(
                                        orderId,
                                        order['table_id'] as int?,
                                      ),
                                      icon: const Icon(
                                        Icons.request_page_outlined,
                                        size: 14,
                                      ),
                                      label: const Text('Request Bill'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  if (type == 'Dine-In' &&
                                      status != 'Billing Pending' &&
                                      status != 'Served')
                                    IconButton(
                                      icon: const Icon(
                                        Icons.move_down,
                                        color: Colors.blue,
                                      ),
                                      // tooltip disabled,
                                      onPressed: () => _showTransferTableDialog(
                                        orderId,
                                        order['table_id'] as int,
                                        tableDisplay,
                                      ),
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
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // --- ORDER TAKING PANEL ---
  Widget _buildOrderTakingPanel() {
    final filteredProducts = _products.where((p) {
      final matchesCat =
          _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch = p.name.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
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
                  onCategorySelected: (cat) =>
                      setState(() => _selectedCategory = cat),
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
            onWaiterSelected: (id, name) => setState(() {
              _selectedWaiterId = id;
              _selectedWaiterName = name;
            }),
            onChefSelected: (id, name) => setState(() {
              _selectedChefId = id;
              _selectedChefName = name;
            }),
            showWaiterAssignment: _showWaiterAssignment,
            showChefAssignment: _showChefAssignment,
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
                  final tableInfo = _tableInfoList.firstWhere(
                    (t) => t.table.id == tableId,
                    orElse: () => _tableInfoList.first,
                  );
                  _selectedTableDisplayName = tableInfo.displayNameForOrder;
                  _orderType = 'Dine-In';
                  _currentOrderGuestCount = tableInfo.combinedCapacity;
                }
              });
            },
            onDecrementCart: _decrementCart,
            onRemoveCartItem: _removeCartItem,
            onEditCartItem: _editCartItem,
            onClearCart: () => setState(() => _cartItems.clear()),
            onSendKOT: _submitWaiterOrder,
            onPrintBill: () {
              if (_selectedTableId == null) return;
              final billMatch = _tableInfoList.where((t) => t.table.id == _selectedTableId);
              final billOrder = billMatch.isNotEmpty ? billMatch.first.activeOrder : null;
              final billOrderId = billOrder == null ? null : (billOrder['id'] as num?)?.toInt();
              if (billOrderId != null) {
                _requestBilling(billOrderId, _selectedTableId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No active order to bill for this table.')),
                );
              }
            },
            onCheckout: () {
              if (_selectedTableId == null) return;
              final checkMatch = _tableInfoList.where((t) => t.table.id == _selectedTableId);
              final checkOrder = checkMatch.isNotEmpty ? checkMatch.first.activeOrder : null;
              final checkOrderId = checkOrder == null ? null : (checkOrder['id'] as num?)?.toInt();
              if (checkOrderId != null) {
                _requestBilling(checkOrderId, _selectedTableId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No active order to checkout for this table.')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
