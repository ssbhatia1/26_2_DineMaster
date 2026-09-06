import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _inventoryItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    final db = await _dbHelper.database;
    final restaurantId = DatabaseHelper.currentRestaurantId;
    _inventoryItems = await db.query(
      'inventory',
      where: 'restaurant_id = ?',
      whereArgs: [restaurantId],
    );
    
    // Insert sample data if empty
    if (_inventoryItems.isEmpty) {
      await db.insert('inventory', {
        'item_name': 'Paneer',
        'current_stock': 10.5,
        'unit': 'kg',
        'low_stock_threshold': 2.0,
        'restaurant_id': restaurantId,
      });
      await db.insert('inventory', {
        'item_name': 'Chicken',
        'current_stock': 5.0,
        'unit': 'kg',
        'low_stock_threshold': 5.0,
        'restaurant_id': restaurantId,
      });
      await db.insert('inventory', {
        'item_name': 'Amul Butter',
        'current_stock': 20.0,
        'unit': 'packets',
        'low_stock_threshold': 5.0,
        'restaurant_id': restaurantId,
      });
      _inventoryItems = await db.query(
        'inventory',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );
    }
    
    setState(() => _isLoading = false);
  }

  void _showAddInventoryDialog() {
    final nameController = TextEditingController();
    final stockController = TextEditingController();
    final unitController = TextEditingController();
    final thresholdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Inventory Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Current Stock'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(labelText: 'Unit (e.g. kg, packets)'),
            ),
            TextField(
              controller: thresholdController,
              decoration: const InputDecoration(labelText: 'Low Stock Threshold'),
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
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  stockController.text.isNotEmpty &&
                  unitController.text.isNotEmpty &&
                  thresholdController.text.isNotEmpty) {
                final db = await _dbHelper.database;
                await db.insert('inventory', {
                  'item_name': nameController.text,
                  'current_stock': double.parse(stockController.text),
                  'unit': unitController.text,
                  'low_stock_threshold': double.parse(thresholdController.text),
                  'restaurant_id': DatabaseHelper.currentRestaurantId,
                });
                Navigator.pop(context);
                _loadInventory();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditInventoryDialog(Map<String, dynamic> item) {
    final nameController = TextEditingController(text: item['item_name']);
    final stockController = TextEditingController(text: item['current_stock'].toString());
    final unitController = TextEditingController(text: item['unit']);
    final thresholdController = TextEditingController(text: item['low_stock_threshold'].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Inventory Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Current Stock'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
            TextField(
              controller: thresholdController,
              decoration: const InputDecoration(labelText: 'Low Stock Threshold'),
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
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  stockController.text.isNotEmpty &&
                  unitController.text.isNotEmpty &&
                  thresholdController.text.isNotEmpty) {
                final db = await _dbHelper.database;
                await db.update(
                  'inventory',
                  {
                    'item_name': nameController.text,
                    'current_stock': double.parse(stockController.text),
                    'unit': unitController.text,
                    'low_stock_threshold': double.parse(thresholdController.text),
                  },
                  where: 'id = ?',
                  whereArgs: [item['id']],
                );
                Navigator.pop(context);
                _loadInventory();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory & Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInventory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inventoryItems.isEmpty
              ? const Center(child: Text('No inventory items found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _inventoryItems.length,
                  itemBuilder: (context, index) {
                    final item = _inventoryItems[index];
                    final currentStock = item['current_stock'] as double;
                    final threshold = item['low_stock_threshold'] as double;
                    final isLow = currentStock <= threshold;

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isLow ? Colors.red.shade50 : Colors.deepPurple.shade50,
                          child: Icon(
                            Icons.inventory,
                            color: isLow ? Colors.red : Colors.deepPurple,
                          ),
                        ),
                        title: Text(
                          item['item_name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Threshold: ${item['low_stock_threshold']} ${item['unit']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${item['current_stock']} ${item['unit']}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isLow ? Colors.red : Colors.black,
                                  ),
                                ),
                                if (isLow)
                                  const Text(
                                    'Low Stock',
                                    style: TextStyle(color: Colors.red, fontSize: 12),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.grey),
                              onPressed: () => _showEditInventoryDialog(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddInventoryDialog,
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
