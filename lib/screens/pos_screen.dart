import 'dart:io';
import 'package:dine_master/core/theme/app_colors.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/product_repository.dart';
import '../models/product_model.dart';
import '../core/database/database_helper.dart';
import '../repositories/table_repository.dart';
import '../models/table_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';
import '../widgets/searchable_dropdown.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_preview_screen.dart';
import '../widgets/food_attributes_badge.dart';

class PosScreen extends StatefulWidget {
  final int? reopenOrderId;
  final int? selectedTableId;
  const PosScreen({super.key, this.reopenOrderId, this.selectedTableId});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with SingleTickerProviderStateMixin {
  final ProductRepository _productRepository = ProductRepository();
  final TableRepository _tableRepository = TableRepository();
  final List<String> _categories = ['All', 'Starters', 'Main Course', 'Breads', 'Beverages', 'Desserts'];
  String _selectedCategory = 'All';
  
  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  List<TableModel> _tables = [];
  List<Map<String, dynamic>> _cartItems = []; // [{ 'product': ProductModel, 'quantity': int }]
  bool _isLoading = true;
  String _selectedOrderType = 'Walk-in Customer';
  int? _selectedTableId;
  final List<String> _orderTypes = ['Dine-In', 'Table Order', 'Delivery', 'Takeaway', 'Online Order', 'Walk-in Customer'];
  String _selectedPaymentType = 'Cash';
  double _discountAmount = 0.0;
  String _discountType = 'Flat'; // Flat or Percentage
  int? _editingOrderId;
  StreamSubscription? _syncSubscription;
  late TabController _posTabController;
  List<Map<String, dynamic>> _activeOrders = [];
  final TextEditingController _customerNameController = TextEditingController(text: 'Walking Customer');
  final TextEditingController _customerPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _posTabController = TabController(length: 2, vsync: this);
    _loadProducts().then((_) {
      if (widget.reopenOrderId != null) {
        _reopenOrder(widget.reopenOrderId!);
      }
    });
    _loadTables().then((_) async {
      if (widget.selectedTableId != null) {
        setState(() {
          _selectedOrderType = 'Table Order';
          _selectedTableId = widget.selectedTableId;
        });

        final db = await DatabaseHelper.instance.database;
        final activeOrders = await db.query(
          'orders',
          where: 'table_id = ? AND status IN (\'Held\', \'Received\', \'Sent to Kitchen\', \'Preparing\', \'Ready\', \'Served\', \'Billing Pending\')',
          whereArgs: [widget.selectedTableId],
          orderBy: 'order_time DESC',
          limit: 1,
        );
        if (activeOrders.isNotEmpty) {
          final activeOrderId = activeOrders.first['id'] as int;
          await _reopenOrder(activeOrderId);
        }
      }
    });
    _loadActiveOrders();

    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted) {
        _loadTables();
        _loadActiveOrders();
      }
    });
  }

  @override
  void dispose() {
    _posTabController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reopenOrder(int orderId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final orderDetails = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      );

      if (orderDetails.isEmpty) return;
      final order = orderDetails.first;

      final items = await db.rawQuery('''
        SELECT oi.*, p.name as product_name 
        FROM order_items oi
        JOIN products p ON oi.product_id = p.id
        WHERE oi.order_id = ?
      ''', [orderId]);

      setState(() {
        _cartItems.clear();
        for (var item in items) {
          final product = _products.firstWhere(
            (p) => p.id == item['product_id'],
            orElse: () => ProductModel(
              id: item['product_id'] as int,
              name: item['product_name'] as String,
              price: item['price'] as double,
              category: '',
              isVeg: 1,
              isAvailable: true,
            ),
          );
          
          _cartItems.add({
            'product': product,
            'quantity': item['quantity'] as int,
          });
        }
        final rawType = order['type'] as String? ?? 'Walk-in Customer';
        if (rawType == 'Dine-In') {
          _selectedOrderType = 'Table Order';
        } else if (rawType == 'Takeaway') {
          _selectedOrderType = 'Walk-in Customer';
        } else if (rawType == 'Delivery') {
          _selectedOrderType = 'Online Order';
        } else {
          _selectedOrderType = rawType;
        }
        _selectedTableId = order['table_id'] as int?;
        _discountAmount = (order['discount_amount'] ?? 0.0) as double;
        _customerNameController.text = order['customer_name'] as String? ?? '';
        _customerPhoneController.text = order['customer_phone'] as String? ?? '';
        _editingOrderId = orderId;
      });
      
      _posTabController.animateTo(0);
      

    } catch (e) {
      print('Error reopening order: $e');
    }
  }

  Future<void> _loadTables() async {
    try {
      final tables = await _tableRepository.getTables();
      setState(() {
        _tables = tables;
      });
    } catch (e) {
      print('Error loading tables: $e');
    }
  }

  Future<void> _loadActiveOrders() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;
      final List<Map<String, dynamic>> orders = await db.rawQuery('''
        SELECT o.*, t.table_number,
               (SELECT COUNT(*) FROM order_items WHERE order_id = o.id) as item_count,
               (SELECT SUM(amount) FROM payments WHERE order_id = o.id) as paid_amount
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.status IN ('Held', 'Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served', 'Billing Pending') AND o.restaurant_id = ?
        ORDER BY o.order_time DESC
      ''', [restaurantId]);

      setState(() {
        _activeOrders = orders;
      });
    } catch (e) {
      print('Error loading active orders: $e');
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      _products = await _productRepository.getProducts();
      
      // Integration with Recipes & Ingredients
      final db = await DatabaseHelper.instance.database;
      
      List<ProductModel> updatedProducts = [];
      for (var product in _products) {
        bool isStockAvailable = true;
        
        // Fetch recipe for this product
        final recipeItems = await db.rawQuery('''
          SELECT recipes.*, ingredients.stock_quantity 
          FROM recipes 
          JOIN ingredients ON recipes.ingredient_id = ingredients.id 
          WHERE recipes.product_id = ?
        ''', [product.id]);
        
        for (var item in recipeItems) {
          final stock = item['stock_quantity'] as double;
          final qtyNeeded = item['quantity_used'] as double;
          if (stock < qtyNeeded) {
            isStockAvailable = false;
            break;
          }
        }
        
        // Combine DB availability and recipe availability
        final finalAvailability = product.isAvailable && isStockAvailable;
        updatedProducts.add(product.copyWith(isAvailable: finalAvailability));
      }
      _products = updatedProducts;
      
      _filterProducts();
    } catch (e) {
      print('Error loading products: $e');
    }
    setState(() => _isLoading = false);
  }

  void _filterProducts() {
    setState(() {
      if (_selectedCategory == 'All') {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((p) => p.category == _selectedCategory).toList();
      }
    });
  }

  void _handleProductTap(ProductModel product) {
    if (product.hasPreferences) {
      _showPreferenceCustomizationDialog(product);
    } else {
      _addToCart(product);
    }
  }

  void _showPreferenceCustomizationDialog(ProductModel product) {
    String? selectedDietary;
    String? selectedTaste;
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.tune, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customize: ${product.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.dietaryPreferences.isNotEmpty) ...[
                  const Text('Dietary Preference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
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
                if (product.tastePreferences.isNotEmpty) ...[
                  const Text('Taste Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
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
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen Instructions / Notes',
                    hintText: 'e.g. Less oil, extra chutney...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
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
                final List<String> parts = [];
                if (selectedDietary != null) parts.add(selectedDietary!);
                if (selectedTaste != null) parts.add(selectedTaste!);
                if (notesCtrl.text.trim().isNotEmpty) parts.add(notesCtrl.text.trim());
                final customNote = parts.isNotEmpty ? parts.join(', ') : null;

                Navigator.pop(context);
                _addToCart(product, customNote);
              },
              child: const Text('Add to Cart'),
            ),
          ],
        ),
      ),
    );
  }

  void _addToCart(ProductModel product, [String? notes]) {
    setState(() {
      final index = _cartItems.indexWhere(
        (item) => item['product'].id == product.id && item['notes'] == notes,
      );
      if (index >= 0) {
        _cartItems[index]['quantity']++;
      } else {
        _cartItems.add({'product': product, 'quantity': 1, 'notes': notes});
      }
    });
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      _cartItems[index]['quantity'] += delta;
      if (_cartItems[index]['quantity'] <= 0) {
        _cartItems.removeAt(index);
      }
    });
  }

  double _getSubtotal() {
    return _cartItems.fold(0.0, (sum, item) => sum + (item['product'].price * item['quantity']));
  }

  double _getTax() {
    final subtotal = _getSubtotal();
    if (subtotal == 0) return 0.0;
    
    final discount = _getDiscount();
    final ratio = (subtotal - discount) / subtotal;
    
    double totalTax = 0.0;
    for (var item in _cartItems) {
      final product = item['product'] as ProductModel;
      final qty = item['quantity'] as int;
      final itemSubtotal = product.price * qty;
      final itemTax = (itemSubtotal * ratio) * (product.gstPercentage / 100);
      totalTax += itemTax;
    }
    return totalTax;
  }

  double _getTotal() {
    return _getSubtotal() - _getDiscount() + _getTax();
  }

  Future<void> _processBilling() async {
    if (_cartItems.isEmpty) {

      return;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final discount = _getDiscount();
      final total = _getTotal();

      int orderId;
      Map<int, int?> productToKotId = {};
      Map<int, String> productToStatus = {};

      final isSplit = _selectedPaymentType == 'Split';

      if (_editingOrderId != null) {
        orderId = _editingOrderId!;

        // Query existing order items to preserve kot_id and status
        final List<Map<String, dynamic>> existingItems = await db.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        for (var item in existingItems) {
          productToKotId[item['product_id'] as int] = item['kot_id'] as int?;
          productToStatus[item['product_id'] as int] = item['status'] as String? ?? 'Pending';
        }

        // Check if order already has an order taker
        final existingOrder = await db.query('orders', columns: ['order_taker_name'], where: 'id = ?', whereArgs: [orderId]);
        final bool hasTaker = existingOrder.isNotEmpty && existingOrder.first['order_taker_name'] != null;

        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Cashier';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        await db.update('orders', {
          'total_amount': total,
          'status': isSplit ? 'Billing Pending' : 'Completed',
          'type': _selectedOrderType,
          'order_time': now,
          'restaurant_id': DatabaseHelper.currentRestaurantId,
          'payment_status': isSplit ? 'Unpaid' : 'Paid',
          'payment_method': _selectedPaymentType,
          'discount_amount': discount,
          'customer_name': _customerNameController.text.trim().isNotEmpty ? _customerNameController.text.trim() : 'Guest',
          'customer_phone': _customerPhoneController.text.trim().isNotEmpty ? _customerPhoneController.text.trim() : null,
          if (!hasTaker) 'order_taker_name': orderTakerName,
          if (!hasTaker) 'order_taker_id': orderTakerId,
          if (_selectedOrderType == 'Table Order' && _selectedTableId != null) 'table_id': _selectedTableId,
        }, where: 'id = ?', whereArgs: [orderId]);

        await db.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      } else {
        // Calculate next sequential order ID
        final maxIdResult = await db.rawQuery('SELECT MAX(id) as max_id FROM orders');
        int nextOrderId = 1;
        if (maxIdResult.isNotEmpty && maxIdResult.first['max_id'] != null) {
          nextOrderId = (maxIdResult.first['max_id'] as int) + 1;
        }
        orderId = nextOrderId;

        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Cashier';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        await db.insert('orders', {
          'id': orderId,
          'total_amount': total,
          'status': isSplit ? 'Billing Pending' : 'Completed',
          'type': _selectedOrderType,
          'order_time': now,
          'restaurant_id': DatabaseHelper.currentRestaurantId,
          'payment_status': isSplit ? 'Unpaid' : 'Paid',
          'payment_method': _selectedPaymentType,
          'discount_amount': discount,
          'customer_name': _customerNameController.text.trim().isNotEmpty ? _customerNameController.text.trim() : 'Guest',
          'customer_phone': _customerPhoneController.text.trim().isNotEmpty ? _customerPhoneController.text.trim() : null,
          'order_taker_name': orderTakerName,
          'order_taker_id': orderTakerId,
          if (_selectedOrderType == 'Table Order' && _selectedTableId != null) 'table_id': _selectedTableId,
        });
      }

      // Insert Order Items
      for (final item in _cartItems) {
        final product = item['product'] as ProductModel;
        final savedKotId = productToKotId[product.id];
        final savedStatus = productToStatus[product.id] ?? 'Pending';

        await db.insert('order_items', {
          'order_id': orderId,
          'product_id': product.id,
          'quantity': item['quantity'],
          'price': product.price,
          'status': savedStatus,
          if (item['notes'] != null) 'notes': item['notes'],
          if (savedKotId != null) 'kot_id': savedKotId,
        });

        // Deduct stock if matching inventory item exists
        final inventory = await db.query(
          'inventory',
          where: 'restaurant_id = ?',
          whereArgs: [DatabaseHelper.currentRestaurantId],
        );
        
        for (var invItem in inventory) {
          final itemName = invItem['item_name'] as String;
          final currentStock = invItem['current_stock'] as double;
          
          if (product.name.toLowerCase().contains(itemName.toLowerCase())) {
            final newStock = currentStock - item['quantity'];
            await db.update(
              'inventory',
              {'current_stock': newStock},
              where: 'id = ?',
              whereArgs: [invItem['id']],
            );
            break; // Assume 1 matching ingredient for simplicity
          }
        }
      }

      // Automatically generate KOT for any new/unassigned items
      await DatabaseHelper.instance.generateKOTForOrder(orderId);

      if (!isSplit) {
        // Insert Payment Record
        await db.insert('payments', {
          'order_id': orderId,
          'amount': total,
          'payment_mode': _selectedPaymentType,
          'payment_time': now,
        });
      }

      // Clear Table Status if Dine-in
      // Clear Table Status if Dine-in or Table Order
      if ((_selectedOrderType == 'Table Order' || _selectedOrderType == 'Dine-In') && _selectedTableId != null) {
        if (!isSplit) {
          // Unmerge and release all associated tables
          await db.update(
            'tables',
            {'status': 'Available', 'merged_with_id': null},
            where: 'id = ? OR merged_with_id = ?',
            whereArgs: [_selectedTableId, _selectedTableId],
          );
        } else {
          await db.update(
            'tables',
            {'status': 'Billing Pending'},
            where: 'id = ?',
            whereArgs: [_selectedTableId],
          );
        }
      }

      // Clear Cart
      setState(() {
        _cartItems.clear();
        _editingOrderId = null;
        _selectedTableId = null;
        _customerNameController.text = 'Walking Customer';
        _customerPhoneController.clear();
      });

      // Broadcast the change instantly via WebSocket
      SyncService.instance.broadcastEvent('database_update', {});

      if (isSplit) {
        _showSplitPaymentCheckoutDialog(orderId, total);
      } else {

      }

      _loadTables();
      _loadActiveOrders();
    } catch (e) {

    }
  }

  Future<void> _holdOrder(String customerName, String customerPhone) async {
    if (_cartItems.isEmpty) {

      return;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final discount = _getDiscount();
      final total = _getTotal();

      int orderId;
      Map<int, int?> productToKotId = {};
      Map<int, String> productToStatus = {};

      if (_editingOrderId != null) {
        orderId = _editingOrderId!;

        // Query existing order items to preserve kot_id and status
        final List<Map<String, dynamic>> existingItems = await db.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        for (var item in existingItems) {
          productToKotId[item['product_id'] as int] = item['kot_id'] as int?;
          productToStatus[item['product_id'] as int] = item['status'] as String? ?? 'Pending';
        }

        final existingOrder = await db.query('orders', columns: ['order_taker_name'], where: 'id = ?', whereArgs: [orderId]);
        final bool hasTaker = existingOrder.isNotEmpty && existingOrder.first['order_taker_name'] != null;

        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Cashier';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        await db.update('orders', {
          'total_amount': total,
          'status': 'Held',
          'type': _selectedOrderType,
          'order_time': now,
          'restaurant_id': DatabaseHelper.currentRestaurantId,
          'payment_status': 'Unpaid',
          'discount_amount': discount,
          'customer_name': customerName.isNotEmpty ? customerName : null,
          'customer_phone': customerPhone.isNotEmpty ? customerPhone : null,
          if (!hasTaker) 'order_taker_name': orderTakerName,
          if (!hasTaker) 'order_taker_id': orderTakerId,
          if (_selectedOrderType == 'Table Order' && _selectedTableId != null) 'table_id': _selectedTableId,
        }, where: 'id = ?', whereArgs: [orderId]);

        await db.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      } else {
        // Calculate next sequential order ID
        final maxIdResult = await db.rawQuery('SELECT MAX(id) as max_id FROM orders');
        int nextOrderId = 1;
        if (maxIdResult.isNotEmpty && maxIdResult.first['max_id'] != null) {
          nextOrderId = (maxIdResult.first['max_id'] as int) + 1;
        }
        orderId = nextOrderId;

        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username') ?? 'Cashier';
        final userList = await db.query('users', where: 'username = ?', whereArgs: [username]);
        String orderTakerName = username;
        int? orderTakerId;
        if (userList.isNotEmpty) {
          orderTakerName = userList.first['name'] as String? ?? username;
          orderTakerId = userList.first['id'] as int?;
        }

        await db.insert('orders', {
          'id': orderId,
          'total_amount': total,
          'status': 'Held',
          'type': _selectedOrderType,
          'order_time': now,
          'restaurant_id': DatabaseHelper.currentRestaurantId,
          'payment_status': 'Unpaid',
          'discount_amount': discount,
          'customer_name': customerName.isNotEmpty ? customerName : null,
          'customer_phone': customerPhone.isNotEmpty ? customerPhone : null,
          'order_taker_name': orderTakerName,
          'order_taker_id': orderTakerId,
          if (_selectedOrderType == 'Table Order' && _selectedTableId != null) 'table_id': _selectedTableId,
        });
      }

      for (final item in _cartItems) {
        final product = item['product'] as ProductModel;
        final savedKotId = productToKotId[product.id];
        final savedStatus = productToStatus[product.id] ?? 'Pending';

        await db.insert('order_items', {
          'order_id': orderId,
          'product_id': product.id,
          'quantity': item['quantity'],
          'price': product.price,
          'status': savedStatus,
          if (item['notes'] != null) 'notes': item['notes'],
          if (savedKotId != null) 'kot_id': savedKotId,
        });
      }

      // Automatically generate KOT for new/unassigned items
      await DatabaseHelper.instance.generateKOTForOrder(orderId);

      // Update table status to Occupied if it is a table order
      if (_selectedOrderType == 'Table Order' && _selectedTableId != null) {
        await db.update(
          'tables',
          {'status': 'Occupied'},
          where: 'id = ?',
          whereArgs: [_selectedTableId],
        );
      }

      setState(() {
        _cartItems.clear();
        _editingOrderId = null;
        _selectedTableId = null;
        _customerNameController.text = 'Walking Customer';
        _customerPhoneController.clear();
      });


      _loadTables();
    } catch (e) {

    }
  }

  Future<void> _confirmDeleteHoldOrder(int orderId, int? tableId, VoidCallback onSuccess) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Hold Order'),
        content: Text('Are you sure you want to cancel and delete hold order #$orderId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.transaction((txn) async {
                await txn.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
                await txn.delete('orders', where: 'id = ?', whereArgs: [orderId]);
                if (tableId != null) {
                  await txn.update(
                    'tables',
                    {'status': 'Available'},
                    where: 'id = ?',
                    whereArgs: [tableId],
                  );
                }
              });
              Navigator.pop(context);
              onSuccess();
              _loadTables();
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _showOrderHistoryAndKotDialog(int orderId) {
    showDialog(
      context: context,
      builder: (context) {
        List<Map<String, dynamic>> kots = [];
        List<Map<String, dynamic>> logs = [];
        bool loading = true;
        Timer? dialogTimer;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> reloadData() async {
              try {
                final db = await DatabaseHelper.instance.database;
                
                // Fetch KOTs
                final kotMaps = await db.query(
                  'kot',
                  where: 'order_id = ?',
                  whereArgs: [orderId],
                  orderBy: 'created_at DESC',
                );

                List<Map<String, dynamic>> fetchedKots = [];
                for (var kot in kotMaps) {
                  final kotId = kot['id'] as int;
                  final itemMaps = await db.rawQuery('''
                    SELECT oi.quantity, p.name as product_name, p.prep_time, p.cook_time
                    FROM order_items oi
                    JOIN products p ON oi.product_id = p.id
                    WHERE oi.kot_id = ?
                  ''', [kotId]);

                  fetchedKots.add({
                    ...kot,
                    'items': itemMaps,
                  });
                }

                // Fetch Logs
                final logMaps = await db.query(
                  'order_status_logs',
                  where: 'order_id = ?',
                  whereArgs: [orderId],
                  orderBy: 'changed_at DESC',
                );

                if (context.mounted) {
                  setDialogState(() {
                    kots = fetchedKots;
                    logs = logMaps;
                    loading = false;
                  });
                }
              } catch (e) {
                print('Error in dialog reload: $e');
              }
            }

            if (loading) {
              reloadData();
              // Setup periodic refresh inside the dialog
              dialogTimer = Timer.periodic(const Duration(seconds: 3), (_) => reloadData());
            }

            return PopScope(
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  dialogTimer?.cancel();
                }
              },
              child: AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order #$orderId - Live History', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                      onPressed: () => reloadData(),
                    ),
                  ],
                ),
                content: loading
                    ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                    : SizedBox(
                        width: 600,
                        height: 450,
                        child: DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(
                                labelColor: AppColors.primary,
                                unselectedLabelColor: Colors.grey,
                                indicatorColor: AppColors.primary,
                                tabs: [
                                  Tab(icon: Icon(Icons.restaurant_menu), text: 'KOT History'),
                                  Tab(icon: Icon(Icons.history_toggle_off), text: 'Status Timeline'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    // Tab 1: KOTs History List
                                    kots.isEmpty
                                        ? const Center(child: Text('No KOTs generated for this order yet.'))
                                        : ListView.builder(
                                            padding: const EdgeInsets.only(top: 12),
                                            itemCount: kots.length,
                                            itemBuilder: (context, index) {
                                              final kot = kots[index];
                                              final status = kot['status'] as String? ?? 'Pending';
                                              final kotItems = kot['items'] as List<Map<String, dynamic>>? ?? [];

                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 12),
                                                child: ExpansionTile(
                                                  title: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'KOT #${kot['id']} (${kot['kot_number'] ?? ''})',
                                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: status == 'Served'
                                                              ? Colors.green.shade50
                                                              : (status == 'Ready' ? Colors.blue.shade50 : Colors.orange.shade50),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          status,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: status == 'Served'
                                                                ? Colors.green
                                                                : (status == 'Ready' ? Colors.blue : Colors.orange),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  subtitle: Text(
                                                    'Chef: ${kot['chef_name'] ?? 'Unassigned'} • Est: ${kot['estimated_time'] ?? 15} mins' +
                                                        (kot['delay_reason'] != null ? '\nDelay: ${kot['delay_reason']}' : ''),
                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                  ),
                                                  children: [
                                                    Padding(
                                                      padding: const EdgeInsets.all(12.0),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Text('Items in KOT:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                          const SizedBox(height: 6),
                                                          ...kotItems.map((item) => Padding(
                                                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                                child: Row(
                                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                  children: [
                                                                    Text('${item['quantity']}x ${item['product_name']}', style: const TextStyle(fontSize: 13)),
                                                                    Text('${(item['prep_time'] ?? 5) + (item['cook_time'] ?? 10)} min', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                                                  ],
                                                                ),
                                                              )),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),

                                    // Tab 2: Logs stepper
                                    logs.isEmpty
                                        ? const Center(child: Text('No status transitions logged yet.'))
                                        : ListView.builder(
                                            padding: const EdgeInsets.only(top: 12),
                                            itemCount: logs.length,
                                            itemBuilder: (context, index) {
                                              final log = logs[index];
                                              final timeStr = log['changed_at'] as String? ?? '';
                                              final time = DateTime.tryParse(timeStr) ?? DateTime.now();

                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12.0),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Padding(
                                                      padding: EdgeInsets.only(top: 4.0),
                                                      child: Icon(Icons.circle, size: 12, color: AppColors.primary),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                            children: [
                                                              Text(
                                                                'Status: ${log['status']}',
                                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                              ),
                                                              Text(
                                                                DateFormat('hh:mm a').format(time),
                                                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                                                              ),
                                                            ],
                                                          ),
                                                          Text(
                                                            'By: ${log['changed_by'] ?? 'System'}',
                                                            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                                          ),
                                                          if (log['notes'] != null && log['notes'].toString().isNotEmpty)
                                                            Text(
                                                              'Notes: ${log['notes']}',
                                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                actions: [
                  TextButton(
                    onPressed: () {
                      dialogTimer?.cancel();
                      Navigator.pop(context);
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showResumeDialog() async {
    final db = await DatabaseHelper.instance.database;
    
    // Load held and active kitchen orders with table numbers
    final List<Map<String, dynamic>> heldOrders = await db.rawQuery('''
      SELECT o.*, t.table_number 
      FROM orders o
      LEFT JOIN tables t ON o.table_id = t.id
      WHERE o.status IN ('Held', 'Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served', 'Billing Pending') AND o.restaurant_id = ?
      ORDER BY o.order_time DESC
    ''', [DatabaseHelper.currentRestaurantId]);

    final searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        List<Map<String, dynamic>> filteredOrders = List.from(heldOrders);

        return StatefulBuilder(
          builder: (context, setState) {
            void filter(String query) {
              setState(() {
                if (query.isEmpty) {
                  filteredOrders = List.from(heldOrders);
                } else {
                  final q = query.toLowerCase();
                  filteredOrders = heldOrders.where((order) {
                    final orderId = order['id'].toString();
                    final tableNum = (order['table_number'] ?? '').toString().toLowerCase();
                    final custName = (order['customer_name'] ?? '').toString().toLowerCase();
                    final orderTime = (order['order_time'] ?? '').toString().toLowerCase();
                    return orderId.contains(q) || tableNum.contains(q) || custName.contains(q) || orderTime.contains(q);
                  }).toList();
                }
              });
            }

            return AlertDialog(
              title: const Text('Resume Active Orders / Checkout Tables'),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: filter,
                      decoration: const InputDecoration(
                        labelText: 'Search by Bill #, Table, Customer Name or Date',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredOrders.isEmpty
                          ? const Center(child: Text('No matching held orders found'))
                          : ListView.builder(
                              itemCount: filteredOrders.length,
                              itemBuilder: (context, index) {
                                final order = filteredOrders[index];
                                final hasTable = order['table_id'] != null;
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text('Bill #${order['id']} - ${hasTable ? 'Table ${order['table_number']}' : 'Walk-in'}'),
                                    subtitle: Text(
                                      'Customer: ${order['customer_name'] ?? 'N/A'}\n'
                                      'Amount: ₹${order['total_amount'].toStringAsFixed(2)} | ${order['order_time'].toString().substring(0, 16).replaceFirst('T', ' ')}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.track_changes, color: AppColors.primary),
                                          // tooltip disabled,
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _showOrderHistoryAndKotDialog(order['id']);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _confirmDeleteHoldOrder(order['id'], order['table_id'], () {
                                            Navigator.pop(context);
                                            _showResumeDialog(); // Refresh
                                          }),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            // Load items into cart
                                            final List<Map<String, dynamic>> items = await db.query(
                                              'order_items',
                                              where: 'order_id = ?',
                                              whereArgs: [order['id']],
                                            );
                                            
                                            this.setState(() {
                                              _cartItems.clear();
                                              for (final item in items) {
                                                final product = _products.firstWhere(
                                                  (p) => p.id == item['product_id'],
                                                  orElse: () => ProductModel(
                                                    id: item['product_id'] as int,
                                                    name: 'Unknown Item',
                                                    price: item['price'] as double,
                                                    category: '',
                                                    isVeg: 1,
                                                    isAvailable: true,
                                                  ),
                                                );
                                                _cartItems.add({'product': product, 'quantity': item['quantity']});
                                              }
                                              _selectedOrderType = order['type'] as String? ?? 'Walk-in Customer';
                                              _selectedTableId = order['table_id'] as int?;
                                              _editingOrderId = order['id'] as int?;
                                            });
                                            Navigator.pop(context);
                                          },
                                          child: const Text('Resume'),
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSplitPaymentCheckoutDialog(int orderId, double totalBill) async {
    final db = await DatabaseHelper.instance.database;

    // Fetch existing payment sum (for partial payments)
    final existingPayments = await db.rawQuery(
      'SELECT SUM(amount) as paid FROM payments WHERE order_id = ?',
      [orderId],
    );
    double alreadyPaid = 0.0;
    if (existingPayments.isNotEmpty && existingPayments.first['paid'] != null) {
      alreadyPaid = (existingPayments.first['paid'] as num).toDouble();
    }

    final double remainingBalance = totalBill - alreadyPaid;

    final cashController = TextEditingController();
    final upiController = TextEditingController();
    final cardController = TextEditingController();
    final walletController = TextEditingController();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              double enteredCash = double.tryParse(cashController.text) ?? 0.0;
              double enteredUpi = double.tryParse(upiController.text) ?? 0.0;
              double enteredCard = double.tryParse(cardController.text) ?? 0.0;
              double enteredWallet = double.tryParse(walletController.text) ?? 0.0;
              double totalEntered = enteredCash + enteredUpi + enteredCard + enteredWallet;
              double diff = totalEntered - remainingBalance;

              Widget statusWidget;
              bool isValid = false;

              if (totalEntered == 0) {
                statusWidget = const Text(
                  'Enter split amounts below.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                );
              } else if (diff.abs() < 0.01) {
                statusWidget = Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Exact Balance Covered! (₹${totalEntered.toStringAsFixed(2)})',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                );
                isValid = true;
              } else if (diff < 0) {
                statusWidget = Row(
                  children: [
                    const Icon(Icons.info, color: Colors.orange, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Partial Payment: ₹${totalEntered.toStringAsFixed(2)} (Due: ₹${(remainingBalance - totalEntered).toStringAsFixed(2)})',
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                );
                isValid = true; // Partial payment is allowed!
              } else {
                statusWidget = Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.amber, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Overpaid: Change Due ₹${diff.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                );
                isValid = true;
              }

              void updateTotals() {
                setStateDialog(() {});
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.call_split, color: AppColors.primary, size: 28),
                    const SizedBox(width: 8),
                    Text('Split / Partial Checkout (#$orderId)'),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          color: AppColors.primaryLight,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Bill:', style: TextStyle(fontSize: 14)),
                                    Text('₹${totalBill.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                if (alreadyPaid > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Already Paid:', style: TextStyle(fontSize: 14, color: Colors.green)),
                                      Text('-₹${alreadyPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Remaining Balance:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                    Text('₹${remainingBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Split breakdown by payment mode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: cashController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.money, color: Colors.green),
                            labelText: 'Cash Amount',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => updateTotals(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: upiController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.qr_code, color: Colors.blue),
                            labelText: 'UPI / QR Amount',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => updateTotals(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: cardController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.credit_card, color: Colors.orange),
                            labelText: 'Card Amount',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => updateTotals(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: walletController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.account_balance_wallet, color: Colors.purple),
                            labelText: 'Wallet Amount',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => updateTotals(),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: statusWidget),
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
                  ElevatedButton(
                    onPressed: !isValid
                        ? null
                        : () async {
                            final now = DateTime.now().toIso8601String();

                            // Record all payment items
                            final List<Map<String, dynamic>> paymentsToInsert = [];
                            if (enteredCash > 0) paymentsToInsert.add({'mode': 'Cash', 'val': enteredCash});
                            if (enteredUpi > 0) paymentsToInsert.add({'mode': 'UPI', 'val': enteredUpi});
                            if (enteredCard > 0) paymentsToInsert.add({'mode': 'Card', 'val': enteredCard});
                            if (enteredWallet > 0) paymentsToInsert.add({'mode': 'Wallet', 'val': enteredWallet});

                            for (var pay in paymentsToInsert) {
                              await db.insert('payments', {
                                'order_id': orderId,
                                'amount': pay['val'],
                                'payment_mode': pay['mode'],
                                'payment_time': now,
                              });
                            }

                            // Calculate final total paid
                            final updatedPayments = await db.rawQuery(
                              'SELECT SUM(amount) as paid FROM payments WHERE order_id = ?',
                              [orderId],
                            );
                            double totalPaid = 0.0;
                            if (updatedPayments.isNotEmpty && updatedPayments.first['paid'] != null) {
                              totalPaid = (updatedPayments.first['paid'] as num).toDouble();
                            }

                            final bool fullyPaid = (totalPaid - totalBill).abs() < 0.01 || totalPaid >= totalBill;

                            String finalStatus = fullyPaid ? 'Completed' : 'Billing Pending';
                            String finalPaymentStatus = fullyPaid ? 'Paid' : 'Partial';

                            // Update order
                            await db.update('orders', {
                              'payment_status': finalPaymentStatus,
                              'status': finalStatus,
                              'payment_method': fullyPaid ? 'Split' : 'Partial',
                            }, where: 'id = ?', whereArgs: [orderId]);

                            // Fetch table associated with order
                            final orderInfo = await db.query('orders', columns: ['table_id'], where: 'id = ?', whereArgs: [orderId]);
                            int? tableId;
                            if (orderInfo.isNotEmpty) {
                              tableId = orderInfo.first['table_id'] as int?;
                            }

                            if (tableId != null) {
                              if (fullyPaid) {
                                await db.update(
                                  'tables',
                                  {'status': 'Available', 'merged_with_id': null},
                                  where: 'id = ? OR merged_with_id = ?',
                                  whereArgs: [tableId, tableId],
                                );
                              } else {
                                await db.update(
                                  'tables',
                                  {'status': 'Billing Pending'},
                                  where: 'id = ?',
                                  whereArgs: [tableId],
                                );
                              }
                            }

                            // Log status history
                            await DatabaseHelper.instance.logOrderStatus(
                              orderId, 
                              finalStatus,
                              notes: 'Split / Partial payment processed. Paid: ₹${totalPaid.toStringAsFixed(2)} / ₹${totalBill.toStringAsFixed(2)}.',
                            );

                            Navigator.pop(context);
                            
                            // Broadcast the change instantly via WebSocket
                            SyncService.instance.broadcastEvent('database_update', {});



                            _loadTables();
                            _loadActiveOrders();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(diff < 0 ? 'Pay Partial' : 'Settle Bill'),
                  ),
                ],
              );
            },
          );
        },
      );
    }
  }

  Widget _buildActiveOrdersTracker() {
    if (_activeOrders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No active tables or orders running.',
              style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: _activeOrders.length,
          itemBuilder: (context, index) {
            final order = _activeOrders[index];
            final status = order['status'] as String? ?? 'Received';
            final orderId = order['id'] as int;
            final total = order['total_amount'] as double? ?? 0.0;
            final paid = order['paid_amount'] as double? ?? 0.0;
            final due = total - paid;
            final hasPaidPartial = paid > 0;
            
            Color badgeColor;
            Color textColor;
            switch (status) {
              case 'Received':
                badgeColor = Colors.blue.shade50;
                textColor = Colors.blue.shade800;
                break;
              case 'Sent to Kitchen':
                badgeColor = Colors.purple.shade50;
                textColor = Colors.purple.shade800;
                break;
              case 'Preparing':
                badgeColor = Colors.orange.shade50;
                textColor = Colors.orange.shade800;
                break;
              case 'Ready':
                badgeColor = Colors.green.shade50;
                textColor = Colors.green.shade800;
                break;
              case 'Served':
                badgeColor = Colors.teal.shade50;
                textColor = Colors.teal.shade800;
                break;
              case 'Billing Pending':
                badgeColor = Colors.red.shade50;
                textColor = Colors.red.shade800;
                break;
              default:
                badgeColor = Colors.grey.shade100;
                textColor = Colors.grey.shade800;
            }

            final isDineIn = order['type'] == 'Table Order';
            final title = isDineIn
                ? 'Table ${order['table_number'] ?? 'N/A'}'
                : '${order['type']} #${order['id']}';

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: status == 'Billing Pending'
                      ? Colors.red.shade200
                      : (status == 'Ready' ? Colors.green.shade200 : Colors.grey.shade200),
                  width: status == 'Billing Pending' || status == 'Ready' ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Waiter: ${order['order_taker_name'] ?? 'None'}',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                    Text(
                      'Time: ${order['order_time'].toString().substring(11, 16)} | Items: ${order['item_count']}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Spacer(),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total: ₹${total.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hasPaidPartial ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            if (hasPaidPartial) ...[
                              Text(
                                'Paid: ₹${paid.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 11, color: Colors.green),
                              ),
                              Text(
                                'Due: ₹${due.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.track_changes, size: 20),
                              color: AppColors.primary,
                              // tooltip disabled,
                              onPressed: () => _showOrderHistoryAndKotDialog(orderId),
                            ),
                            IconButton(
                              icon: const Icon(Icons.payment, size: 20),
                              color: Colors.green,
                              // tooltip disabled,
                              onPressed: () {
                                _showSplitPaymentCheckoutDialog(orderId, total);
                              },
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                await _reopenOrder(orderId);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Checkout', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 950) {
          return _buildDesktopLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  Widget _buildDesktopLayout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Row(
        children: [
          // Left Side: Tab layout for Menu or Active Floor Tracker
          Expanded(
            flex: 7,
            child: Container(
              color: isDark ? const Color(0xFF141416) : Colors.grey.shade50,
              child: Column(
                children: [
                  Container(
                    color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                    child: TabBar(
                      controller: _posTabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primary,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.restaurant_menu),
                          text: 'Menu & Ordering',
                        ),
                        Tab(
                          icon: Icon(Icons.dashboard_customize),
                          text: 'Active Floor Tracker',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _posTabController,
                      children: [
                        _buildMenuAndOrderingTab(context, isDark),
                        _buildActiveOrdersTracker(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Side: Cart & Billing
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F0F11) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: SafeArea(
                child: _buildCartPanel(context, isDark, isMobile: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalQty = _cartItems.fold<int>(0, (sum, item) => sum + (item['quantity'] as int));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('POS Terminal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          elevation: 0,
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(icon: Icon(Icons.restaurant_menu, size: 20), text: 'Menu'),
              const Tab(icon: Icon(Icons.table_restaurant, size: 20), text: 'Floor'),
              Tab(
                icon: Badge(
                  label: Text('$totalQty'),
                  isLabelVisible: totalQty > 0,
                  child: const Icon(Icons.shopping_cart, size: 20),
                ),
                text: 'Cart',
              ),
            ],
          ),
        ),
        body: Container(
          color: isDark ? const Color(0xFF141416) : Colors.grey.shade50,
          child: TabBarView(
            children: [
              _buildMenuAndOrderingTab(context, isDark),
              _buildActiveOrdersTracker(),
              SafeArea(
                child: _buildCartPanel(context, isDark, isMobile: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuAndOrderingTab(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          TextField(
            onChanged: (value) {
              setState(() {
                if (value.isEmpty) {
                  _filterProducts();
                } else {
                  _filteredProducts = _products.where((p) => p.name.toLowerCase().contains(value.toLowerCase())).toList();
                }
              });
            },
            decoration: InputDecoration(
              hintText: 'Search products by name or code...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: isDark ? Colors.grey.shade900 : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Categories Horizontal List
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(category, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = category;
                        _filterProducts();
                      });
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Products Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? const Center(child: Text('No products found'))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _buildProductCard(product);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel(BuildContext context, bool isDark, {bool isMobile = false}) {
    final subtotal = _getSubtotal();
    final tax = _getTax();
    final total = _getTotal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cart Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_cart_outlined, color: AppColors.primaryMaterialColor[400]!),
                  const SizedBox(width: 8),
                  Text(
                    _editingOrderId != null ? 'Edit Order #${_editingOrderId}' : 'New Check-out',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_editingOrderId != null)
                    IconButton(
                      icon: const Icon(Icons.track_changes, color: AppColors.primary, size: 20),
                      // tooltip disabled,
                      onPressed: () => _showOrderHistoryAndKotDialog(_editingOrderId!),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.blue, size: 20),
                    // tooltip disabled,
                    onPressed: _showResumeDialog,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                    // tooltip disabled,
                    onPressed: () {
                      setState(() {
                        _cartItems.clear();
                        _editingOrderId = null;
                        _customerNameController.text = 'Walking Customer';
                        _customerPhoneController.clear();
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Customer Details Row
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customerNameController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.person_outline, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _customerPhoneController,
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Contact Phone',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.phone_outlined, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Order Type Selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: DropdownButtonFormField<String>(
            value: _selectedOrderType,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Order Type',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: _orderTypes.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedOrderType = value!;
              });
            },
          ),
        ),

        // Table Selection (Dine In)
        if (_selectedOrderType == 'Table Order') ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: SearchableDropdown<TableModel>(
                    // Only show merged group anchors so a merged group is selected
                    // as a single entity (members are hidden).
                    items: _tables.where((t) => t.mergedWithId == null).toList(),
                    value: _selectedTableId != null && _tables.any((t) => t.id == _selectedTableId)
                        ? _tables.firstWhere((t) => t.id == _selectedTableId)
                        : null,
                    labelText: 'Select Table',
                    hintText: 'Search table...',
                    itemToString: (t) {
                      final members = _tables.where((m) => m.mergedWithId == t.id).toList();
                      final cap = t.capacity + members.fold<int>(0, (sum, m) => sum + m.capacity);
                      final label = members.isEmpty
                          ? 'Table ${t.tableNumber}'
                          : '${[t, ...members].map((m) => m.tableNumber).join(' + ')} (Merged)';
                      return '$label (Cap: $cap)';
                    },
                    filterFn: (t, query) => t.tableNumber.toLowerCase().contains(query.toLowerCase()),
                    onChanged: (val) async {
                      setState(() {
                        _selectedTableId = val?.id;
                      });
                      if (val != null) {
                        final db = await DatabaseHelper.instance.database;
                        final activeOrders = await db.query(
                          'orders',
                          where: 'table_id = ? AND status IN (\'Held\', \'Received\', \'Sent to Kitchen\', \'Preparing\', \'Ready\', \'Served\', \'Billing Pending\')',
                          whereArgs: [val.id],
                          orderBy: 'order_time DESC',
                          limit: 1,
                        );
                        if (activeOrders.isNotEmpty) {
                          final activeOrderId = activeOrders.first['id'] as int;
                          await _reopenOrder(activeOrderId);
                        } else {
                          setState(() {
                            _cartItems.clear();
                            _editingOrderId = null;
                          });
                        }
                      }
                    },
                    prefixIcon: const Icon(Icons.table_restaurant, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined, color: AppColors.primary),
                  onPressed: _showAdvancedBookingDialog,
                  // tooltip disabled,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        ],
        const Divider(height: 1),

        // Cart Items List
        Expanded(
          child: _cartItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_basket_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text('Cart is empty', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _cartItems.length,
                  itemBuilder: (context, index) {
                    final item = _cartItems[index];
                    final product = item['product'] as ProductModel;
                    final qty = item['quantity'] as int;
                    final isVeg = product.isVeg == 1;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                      ),
                      color: isDark ? const Color(0xFF1E1E24) : Colors.grey.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 12,
                              color: isVeg ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '₹${product.price} each',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  if (item['notes'] != null && item['notes'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primaryMaterialColor[200]!, width: 0.6),
                                      ),
                                      child: Text(
                                        '📝 ${item['notes']}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.primaryMaterialColor[700]!,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                                  onPressed: () => _updateQuantity(index, -1),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                                Text('$qty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 18),
                                  onPressed: () => _updateQuantity(index, 1),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${(product.price * qty).toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),

        // Billing Details
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Column(
            children: [
              _buildBillRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discount (${_discountType == 'Percentage' ? '${_discountAmount}%' : '₹${_discountAmount}'})',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Adjust', style: TextStyle(fontSize: 12)),
                    onPressed: _showDiscountDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              _buildBillRow('GST', '₹${tax.toStringAsFixed(2)}'),
              const Divider(height: 8),
              _buildBillRow('Total Amount', '₹${total.toStringAsFixed(2)}', isTotal: true),
              const SizedBox(height: 12),
              
              DropdownButtonFormField<String>(
                value: _selectedPaymentType,
                items: ['Cash', 'UPI', 'Card', 'Net Banking', 'Wallet', 'Split'].map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) => setState(() => _selectedPaymentType = val!),
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Payment Method',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('PRINT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: _generateCartPdf,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('PREVIEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: _previewCartPdf,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('SAVE DRAFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => _holdOrder(_customerNameController.text, _customerPhoneController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('PAY & SETTLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _processBilling,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _getDiscount() {
    if (_discountType == 'Percentage') {
      return _getSubtotal() * (_discountAmount / 100);
    }
    return _discountAmount;
  }

  void _showDiscountDialog() {
    final controller = TextEditingController(text: _discountAmount.toString());
    String type = _discountType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Discount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                items: ['Flat', 'Percentage'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) => setState(() => type = val!),
                decoration: const InputDecoration(labelText: 'Discount Type'),
              ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Amount / Percentage'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                this.setState(() {
                  _discountAmount = double.tryParse(controller.text) ?? 0.0;
                  _discountType = type;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetails(ProductModel product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: ${product.category}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Price: ₹${product.price}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                const SizedBox(width: 4),
                Text(product.isVeg == 1
                    ? 'Veg'
                    : (product.isVeg == 2
                        ? 'Egg'
                        : (product.isVeg == 3
                            ? 'Jain'
                            : 'Non-Veg'))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: ${product.isAvailable ? 'Available' : 'Out of Stock'}'),
            const SizedBox(height: 16),
            const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(product.description ?? 'No description available.'),
            if (product.ingredients != null && product.ingredients!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Ingredients:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: product.ingredients!.split(',').where((s) => s.trim().isNotEmpty).map((ing) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(ing.trim(), style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                )).toList(),
              ),
            ],
            if (product.recipeSteps != null && product.recipeSteps!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Recipe Steps / Instructions:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...product.recipeSteps!.split('\n').where((s) => s.trim().isNotEmpty).map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    Expanded(child: Text(step)),
                  ],
                ),
              )).toList(),
            ],
            if (product.prepTime != null || product.cookTime != null || product.servings != null || product.difficulty != null) ...[
              const SizedBox(height: 16),
              const Text('Preparation Info:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (product.prepTime != null)
                    _buildPrepChip(Icons.timer_outlined, 'Prep: ${product.prepTime} mins'),
                  if (product.cookTime != null)
                    _buildPrepChip(Icons.dinner_dining_outlined, 'Cook: ${product.cookTime} mins'),
                  if (product.servings != null)
                    _buildPrepChip(Icons.people_outline, 'Servings: ${product.servings}'),
                  if (product.difficulty != null)
                    _buildPrepChip(Icons.assignment_outlined, 'Difficulty: ${product.difficulty}'),
                ],
              ),
            ],
            if (product.videoPath != null && product.videoPath!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                label: const Text('Watch Tutorial Video', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                onPressed: () {
                  _showVideoTutorialDialog(product.videoPath!, product.name);
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _addToCart(product);
            },
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );
  }

  Widget _buildPrepChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showVideoTutorialDialog(String path, String productName) {
    final file = File(path);
    if (!file.existsSync()) {

      return;
    }

    final controller = VideoPlayerController.file(file);
    bool isInitialized = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (!isInitialized) {
            controller.initialize().then((_) {
              setState(() {
                isInitialized = true;
              });
            });
          }

          return AlertDialog(
            title: Text('$productName - Tutorial Video'),
            content: SizedBox(
              width: 500,
              child: isInitialized
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(controller),
                          _VideoOverlay(controller: controller),
                          VideoProgressIndicator(controller, allowScrubbing: true),
                        ],
                      ),
                    )
                  : const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final uri = Uri.file(path);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: const Text('Play in System Player'),
              ),
              TextButton(
                onPressed: () {
                  controller.dispose();
                  Navigator.pop(context);
                },
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    ).then((_) => controller.dispose());
  }

  void _showAdvancedBookingDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Advanced Table Booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Customer Name'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}'),
                    TextButton(
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null && picked != selectedDate) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: const Text('Select Date'),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Time: ${selectedTime.format(context)}'),
                    TextButton(
                      onPressed: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null && picked != selectedTime) {
                          setState(() {
                            selectedTime = picked;
                          });
                        }
                      },
                      child: const Text('Select Time'),
                    ),
                  ],
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
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
              onPressed: () async {
                if (nameController.text.isNotEmpty && _selectedTableId != null) {
                  final db = await DatabaseHelper.instance.database;
                  final bookingTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  ).toIso8601String();

                  await db.insert('bookings', {
                    'table_id': _selectedTableId,
                    'booking_time': bookingTime,
                    'status': 'Confirmed',
                    'notes': notesController.text,
                    'restaurant_id': DatabaseHelper.currentRestaurantId,
                  });

                  // Update table status to Reserved
                  await db.update(
                    'tables',
                    {'status': 'Reserved'},
                    where: 'id = ?',
                    whereArgs: [_selectedTableId],
                  );

                  Navigator.pop(context);

                } else {

                }
              },
              child: const Text('Book'),
            ),
          ],
        ),
      ),
    );
  }

  Future<pw.Document?> _createCartPdfDocument() async {
    if (_cartItems.isEmpty) {

      return null;
    }
    
    final pdf = pw.Document();
    final now = DateTime.now();
    final subtotal = _getSubtotal();
    final discount = _getDiscount();
    final tax = _getTax();
    final total = _getTotal();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('RESTOPRO ERP', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Center(
                child: pw.Text('Order Receipt Draft', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic)),
              ),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.Text('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}'),
              pw.Text('Type: $_selectedOrderType'),
              if (_selectedOrderType == 'Table Order' && _selectedTableId != null)
                pw.Text('Table: ${_tables.firstWhere((t) => t.id == _selectedTableId).tableNumber}'),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              ..._cartItems.map((item) {
                final product = item['product'] as ProductModel;
                final qty = item['quantity'] as int;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text('${product.name} x$qty')),
                      pw.Text('Rs. ${(product.price * qty).toStringAsFixed(2)}'),
                    ],
                  ),
                );
              }).toList(),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:'),
                  pw.Text('Rs. ${subtotal.toStringAsFixed(2)}'),
                ],
              ),
              if (discount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount:'),
                    pw.Text('-Rs. ${discount.toStringAsFixed(2)}'),
                  ],
                ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('GST:'),
                  pw.Text('Rs. ${tax.toStringAsFixed(2)}'),
                ],
              ),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Amount:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${total.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Center(
                child: pw.Text('Thank you! Please pay at cashier.', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  Future<void> _generateCartPdf() async {
    final pdf = await _createCartPdfDocument();
    if (pdf == null) return;
    try {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e) {

    }
  }

  Future<void> _previewCartPdf() async {
    final pdf = await _createCartPdfDocument();
    if (pdf == null) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          title: 'Preview Invoice',
          buildPdf: (format) async => pdf.save(),
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
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
          onTap: isAvailable ? () => _handleProductTap(product) : null,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(color: typeColor.withOpacity(0.4), width: 1.5),
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
                        IconButton(
                          icon: const Icon(Icons.info_outline, color: Colors.grey, size: 18),
                          onPressed: () => _showProductDetails(product),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800.withOpacity(0.5) : AppColors.primaryLight.withOpacity(0.5),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                product.category,
                                style: const TextStyle(color: AppColors.primary, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isAvailable)
                Container(
                  color: Colors.black.withOpacity(0.05),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'SOLD OUT',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.primary : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoOverlay({required this.controller});

  @override
  State<_VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends State<_VideoOverlay> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isPlaying = controller.value.isPlaying;

    return GestureDetector(
      onTap: () {
        setState(() {
          isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Container(
        color: Colors.black12,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: isPlaying
                ? const SizedBox.shrink()
                : const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                  ),
          ),
        ),
      ),
    );
  }
}
