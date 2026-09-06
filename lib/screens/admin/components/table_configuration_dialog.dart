import 'package:flutter/material.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import '../../../core/database/database_helper.dart';

class TableConfigurationDialog extends StatefulWidget {
  const TableConfigurationDialog({super.key});

  @override
  State<TableConfigurationDialog> createState() => _TableConfigurationDialogState();
}

class _TableConfigurationDialogState extends State<TableConfigurationDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _tableTypes = [];
  List<Map<String, dynamic>> _tableSections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {})); // To update 'Add New' button label
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;
    final restId = DatabaseHelper.currentRestaurantId;
    
    final types = await db.query('table_types', where: 'restaurant_id = ?', whereArgs: [restId]);
    final sections = await db.query('table_sections', where: 'restaurant_id = ?', whereArgs: [restId]);
    
    if (mounted) {
      setState(() {
        _tableTypes = types;
        _tableSections = sections;
        _isLoading = false;
      });
    }
  }

  Future<void> _addItem(String table, String name) async {
    final db = await DatabaseHelper.instance.database;
    final restId = DatabaseHelper.currentRestaurantId;
    try {
      await db.insert(table, {'name': name, 'restaurant_id': restId});
      _loadData();
    } catch (e) {
      if (mounted) {
        if(false) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item may already exist!')));
      }
    }
  }

  Future<void> _deleteItem(String table, int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
    _loadData();
  }

  void _showAddDialog(String table, String title) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add $title'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: '$title Name', border: const OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _addItem(table, ctrl.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, String table) {
    if (items.isEmpty) {
      return const Center(child: Text('No items found.'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item['name'] as String),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteItem(table, item['id'] as int),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Table Configuration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'Table Types'),
                Tab(text: 'Restaurant Rooms / Sections'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_tableTypes, 'table_types'),
                        _buildList(_tableSections, 'table_sections'),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (_tabController.index == 0) {
                  _showAddDialog('table_types', 'Table Type');
                } else {
                  _showAddDialog('table_sections', 'Section/Room');
                }
              },
              icon: const Icon(Icons.add),
              label: Text('Add New ${_tabController.index == 0 ? 'Type' : 'Section'}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
