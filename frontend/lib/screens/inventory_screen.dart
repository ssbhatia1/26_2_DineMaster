import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/database/database_helper.dart';
import '../services/backend_api_client.dart';
import 'package:dine_master/core/theme/app_colors.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _inventoryItems = [];
  bool _isLoading = true;

  // Filters
  String _searchQuery = '';
  String _filterStatus = 'All'; // All, Healthy, Low Stock, Out of Stock

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
  setState(() => _isLoading = true);

  try {
    if (kIsWeb) {
      final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;
      final response = await BackendApiClient().getJson(
        '/api/inventory?restaurantId=$restaurantId',
      );

      final List<dynamic> items = response is List
          ? response
          : (response['content'] as List<dynamic>? ?? []);

      _inventoryItems = items.map<Map<String, dynamic>>((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return {
          ...item,
          'id': item['id'],
          'item_name': item['itemName'] ?? item['item_name'] ?? '',
          'current_stock': item['currentStock'] ?? item['current_stock'] ?? 0,
          'low_stock_threshold':
              item['lowStockThreshold'] ?? item['low_stock_threshold'] ?? 0,
          'unit': item['unit'] ?? '',
          'restaurant_id': item['restaurantId'] ?? item['restaurant_id'],
          'expiry_date': item['expiryDate'] ?? item['expiry_date'],
        };
      }).toList();
    } else {
      final db = await _dbHelper.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;
      _inventoryItems = await db.query(
        'inventory',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
        orderBy: 'item_name ASC',
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load inventory: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  List<Map<String, dynamic>> get _filteredItems {
    return _inventoryItems.where((item) {
      // Search
      final name = (item['item_name'] as String).toLowerCase();
      if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // Status
      final stock = (item['current_stock'] as num).toDouble();
      final threshold = (item['low_stock_threshold'] as num).toDouble();
      
      if (_filterStatus == 'Out of Stock' && stock <= 0) return _filterStatus == 'Out of Stock'; // Actually, if filter is out of stock, we ONLY want stock <= 0.
      if (_filterStatus == 'Out of Stock' && stock > 0) return false;
      if (_filterStatus == 'Low Stock' && (stock <= 0 || stock > threshold)) return false;
      if (_filterStatus == 'Healthy' && stock <= threshold) return false;

      return true;
    }).toList();
  }

  // KPIs
  int get _totalItems => _inventoryItems.length;
  int get _lowStockCount => _inventoryItems.where((i) => (i['current_stock'] as num) > 0 && (i['current_stock'] as num) <= (i['low_stock_threshold'] as num)).length;
  int get _outOfStockCount => _inventoryItems.where((i) => (i['current_stock'] as num) <= 0).length;

  void _showAddInventoryDialog() {
    final nameController = TextEditingController();
    final stockController = TextEditingController();
    final unitController = TextEditingController();
    final thresholdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Item', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item Name', prefixIcon: Icon(Icons.inventory_2_outlined)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: stockController,
                      decoration: const InputDecoration(labelText: 'Initial Stock', prefixIcon: Icon(Icons.numbers)),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: unitController,
                      decoration: const InputDecoration(labelText: 'Unit (e.g. kg)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: thresholdController,
                decoration: const InputDecoration(labelText: 'Low Stock Threshold', prefixIcon: Icon(Icons.warning_amber)),
                keyboardType: TextInputType.number,
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  stockController.text.isEmpty ||
                  unitController.text.trim().isEmpty ||
                  thresholdController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all fields.')),
                );
                return;
              }

              try {
                final stock = double.tryParse(stockController.text);
                final threshold = double.tryParse(thresholdController.text);

                if (stock == null || threshold == null || stock < 0 || threshold < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter valid non-negative stock values.')),
                  );
                  return;
                }

                await BackendApiClient().postJson('/api/inventory', {
                  'itemName': nameController.text.trim(),
                  'currentStock': stock,
                  'unit': unitController.text.trim(),
                  'lowStockThreshold': threshold,
                  'expiryDate': null,
                  'restaurantId': DatabaseHelper.currentRestaurantId ?? 1,
                });

                if (!mounted) return;
                Navigator.pop(context);
                await _loadInventory();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add item: $e')),
                  );
                }
              }
            },
            child: const Text('Add Item'),
          ),
        ],
      ),
    );
  }

  void _showAdjustStockDialog(Map<String, dynamic> item) {
    final qtyController = TextEditingController();
    String mode = 'Add'; // Add, Deduct, Set

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Adjust Stock: ${item['item_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Stock: ${item['current_stock']} ${item['unit']}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Add', label: Text('Add (+)')),
                    ButtonSegment(value: 'Deduct', label: Text('Deduct (-)')),
                    ButtonSegment(value: 'Set', label: Text('Set New')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (val) {
                    setDialogState(() => mode = val.first);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyController,
                  decoration: InputDecoration(
                    labelText: mode == 'Set' ? 'New Total Quantity' : 'Quantity to $mode',
                    suffixText: item['unit'],
                    border: const OutlineInputBorder(),
                  ),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                onPressed: () async {
                  final val = double.tryParse(qtyController.text);
                  if (val != null) {

                    try {
                      await BackendApiClient().patchJson(
                        '/api/inventory/${item['id']}/stock',
                        {
                          'mode': mode.toLowerCase(),
                          'quantity': val,
                        },
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to adjust stock: $e')),
                        );
                      }
                      return;
                    }
                    Navigator.pop(context);
                    _loadInventory();
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showEditDetailsDialog(Map<String, dynamic> item) {
    final nameController = TextEditingController(text: item['item_name']);
    final unitController = TextEditingController(text: item['unit']);
    final thresholdController = TextEditingController(text: item['low_stock_threshold'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Item Name')),
            TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unit')),
            TextField(controller: thresholdController, decoration: const InputDecoration(labelText: 'Low Stock Threshold'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (nameController.text.isNotEmpty && unitController.text.isNotEmpty && thresholdController.text.isNotEmpty) {
                try {
                await BackendApiClient().putJson(
                  '/api/inventory/${item['id']}',
                  {
                    'itemName': nameController.text.trim(),
                    'currentStock': (item['current_stock'] as num).toDouble(),
                    'unit': unitController.text.trim(),
                    'lowStockThreshold':
                        double.tryParse(thresholdController.text) ?? 0.0,
                    'expiryDate': item['expiry_date'],
                    'restaurantId': item['restaurant_id'] ??
                        DatabaseHelper.currentRestaurantId ?? 1,
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                _loadInventory();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update item: $e')),
                  );
                }
              }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color, {bool isMobile = false}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: isMobile ? 18 : 24,
              backgroundColor: color.withAlpha(25),
              child: Icon(icon, color: color, size: isMobile ? 20 : 28),
            ),
            SizedBox(width: isMobile ? 10 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: isMobile ? 11 : 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isMobile ? 2 : 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(double stock, double threshold) {
    String label;
    Color color;
    if (stock <= 0) {
      label = 'Out of Stock';
      color = Colors.red;
    } else if (stock <= threshold) {
      label = 'Low Stock';
      color = Colors.orange;
    } else {
      label = 'Healthy';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Inventory Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 8),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(isMobile ? 'New Item' : 'New Item', style: const TextStyle(fontSize: 13)),
            onPressed: _showAddInventoryDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Cards
                  if (isMobile) ...[
                    Row(
                      children: [
                        Expanded(child: _buildKpiCard('Total Items', _totalItems.toString(), Icons.inventory_2, AppColors.primary, isMobile: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildKpiCard('Healthy', (_totalItems - _lowStockCount - _outOfStockCount).toString(), Icons.check_circle, Colors.green, isMobile: true)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildKpiCard('Low Stock', _lowStockCount.toString(), Icons.warning_amber_rounded, Colors.orange, isMobile: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildKpiCard('Out of Stock', _outOfStockCount.toString(), Icons.error_outline, Colors.red, isMobile: true)),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(child: _buildKpiCard('Total Items', _totalItems.toString(), Icons.inventory_2, AppColors.primary)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKpiCard('Healthy Stock', (_totalItems - _lowStockCount - _outOfStockCount).toString(), Icons.check_circle, Colors.green)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKpiCard('Low Stock', _lowStockCount.toString(), Icons.warning_amber_rounded, Colors.orange)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKpiCard('Out of Stock', _outOfStockCount.toString(), Icons.error_outline, Colors.red)),
                      ],
                    ),
                  ],
                  SizedBox(height: isMobile ? 12 : 24),

                  // Search and Filters
                  if (isMobile) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search items...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                          onChanged: (val) {
                            setState(() => _searchQuery = val);
                          },
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ToggleButtons(
                            borderRadius: BorderRadius.circular(8),
                            isSelected: [
                              _filterStatus == 'All',
                              _filterStatus == 'Healthy',
                              _filterStatus == 'Low Stock',
                              _filterStatus == 'Out of Stock',
                            ],
                            onPressed: (index) {
                              setState(() {
                                if (index == 0) _filterStatus = 'All';
                                if (index == 1) _filterStatus = 'Healthy';
                                if (index == 2) _filterStatus = 'Low Stock';
                                if (index == 3) _filterStatus = 'Out of Stock';
                              });
                            },
                            children: const [
                              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('All')),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Healthy')),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Low')),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Out')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search items...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            ),
                            onChanged: (val) {
                              setState(() => _searchQuery = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        ToggleButtons(
                          borderRadius: BorderRadius.circular(8),
                          isSelected: [
                            _filterStatus == 'All',
                            _filterStatus == 'Healthy',
                            _filterStatus == 'Low Stock',
                            _filterStatus == 'Out of Stock',
                          ],
                          onPressed: (index) {
                            setState(() {
                              if (index == 0) _filterStatus = 'All';
                              if (index == 1) _filterStatus = 'Healthy';
                              if (index == 2) _filterStatus = 'Low Stock';
                              if (index == 3) _filterStatus = 'Out of Stock';
                            });
                          },
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('All')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Healthy')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Low')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Out')),
                          ],
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: isMobile ? 12 : 20),

                  // Data Display (Cards on mobile, Table on desktop)
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Colors.white,
                      child: items.isEmpty
                          ? const Center(child: Text('No items match your filters.'))
                          : isMobile
                              ? ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: items.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final stock = (item['current_stock'] as num).toDouble();
                                    final threshold = (item['low_stock_threshold'] as num).toDouble();

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item['item_name'],
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _buildStatusChip(stock, threshold),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Stock: ',
                                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                                  ),
                                                  Text(
                                                    '$stock ${item['unit']}',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: stock <= threshold ? Colors.red : Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '(Min: $threshold)',
                                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Tooltip(
                                                    message: 'Adjust Stock',
                                                    child: IconButton(
                                                      icon: const Icon(Icons.sync_alt, color: Colors.blue, size: 20),
                                                      onPressed: () => _showAdjustStockDialog(item),
                                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Tooltip(
                                                    message: 'Edit Details',
                                                    child: IconButton(
                                                      icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
                                                      onPressed: () => _showEditDetailsDialog(item),
                                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : Column(
                                  children: [
                                    // Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      decoration: BoxDecoration(
                                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                        color: Colors.grey.shade50,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(flex: 3, child: Text('ITEM NAME', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
                                          Expanded(flex: 2, child: Text('CURRENT STOCK', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
                                          Expanded(flex: 2, child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
                                          SizedBox(width: 120, child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700), textAlign: TextAlign.center)),
                                        ],
                                      ),
                                    ),
                                    // Rows
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: items.length,
                                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          final stock = (item['current_stock'] as num).toDouble();
                                          final threshold = (item['low_stock_threshold'] as num).toDouble();

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(item['item_name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                                      Text('Min: $threshold ${item['unit']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        '$stock',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                          color: stock <= threshold ? Colors.red : Colors.black87,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(item['unit'], style: TextStyle(color: Colors.grey.shade600)),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: _buildStatusChip(stock, threshold),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 120,
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Tooltip(
                                                        message: 'Adjust Stock',
                                                        child: IconButton(
                                                          icon: const Icon(Icons.sync_alt, color: Colors.blue),
                                                          onPressed: () => _showAdjustStockDialog(item),
                                                          splashRadius: 20,
                                                        ),
                                                      ),
                                                      Tooltip(
                                                        message: 'Edit Details',
                                                        child: IconButton(
                                                          icon: const Icon(Icons.edit, color: Colors.grey),
                                                          onPressed: () => _showEditDetailsDialog(item),
                                                          splashRadius: 20,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}





