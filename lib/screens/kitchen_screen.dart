import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../services/sync_service.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _kots = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  StreamSubscription? _syncSubscription;

  // Filters & Sorting state
  bool _showHistoryArchive = false;
  String _selectedTab = 'All'; // All, Pending, Preparing, Ready, Served, Delayed
  String _selectedSection = 'All'; // All, Chinese, Tandoor, Fast Food, Main Course, Dessert, Beverages
  String _sortBy = 'Oldest First'; // Oldest First, Priority, Fastest Prep, Table
  String _searchQuery = '';

  // Auto delay prompt tracking
  final Set<int> _delayPromptedKotIds = {};
  final List<int> _delayPromptQueue = [];
  bool _delayDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadKOTs();
    
    // Live WebSocket synchronization
    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted) {
        _loadKOTs(silent: true);
      }
    });

    // Safety fallback poll every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadKOTs(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadKOTs({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final db = await _dbHelper.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;

      // Fetch KOTs for the current restaurant
      final List<Map<String, dynamic>> kotMaps = await db.query(
        'kot',
        where: 'order_id IN (SELECT id FROM orders WHERE restaurant_id = ?)',
        whereArgs: [restaurantId],
        orderBy: 'created_at DESC',
      );

      List<Map<String, dynamic>> kots = [];

      for (final kotMap in kotMaps) {
        final kotId = kotMap['id'] as int;
        final orderId = kotMap['order_id'] as int;

        final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
          SELECT oi.quantity, p.name as product_name, oi.status as item_status, 
                 p.prep_time, p.cook_time, oi.notes as item_notes, p.category as product_category
          FROM order_items oi
          JOIN products p ON oi.product_id = p.id
          WHERE oi.kot_id = ?
        ''', [kotId]);

        // Query order details
        final List<Map<String, dynamic>> orderMaps = await db.query(
          'orders',
          columns: ['table_id', 'type', 'notes', 'customer_name'],
          where: 'id = ?',
          whereArgs: [orderId],
        );

        String tableNumber = 'Takeaway';
        String orderType = 'Takeaway';
        String notes = '';
        String customerName = 'Guest';

        if (orderMaps.isNotEmpty) {
          orderType = orderMaps.first['type'] as String? ?? 'Takeaway';
          notes = orderMaps.first['notes'] as String? ?? '';
          customerName = orderMaps.first['customer_name'] as String? ?? 'Guest';
          final tableId = orderMaps.first['table_id'] as int?;

          if (tableId != null) {
            final List<Map<String, dynamic>> tableMaps = await db.query(
              'tables',
              columns: ['table_number'],
              where: 'id = ?',
              whereArgs: [tableId],
            );
            if (tableMaps.isNotEmpty) {
              tableNumber = tableMaps.first['table_number'] as String;
            }
          }
        }

        kots.add({
          'id': kotId,
          'order_id': orderId,
          'kot_number': kotMap['kot_number'],
          'table_number': tableNumber,
          'type': orderType,
          'notes': notes,
          'customer_name': customerName,
          'status': kotMap['status'] ?? 'Pending',
          'time': kotMap['created_at'],
          'started_cooking_at': kotMap['started_cooking_at'],
          'ready_at': kotMap['ready_at'],
          'served_at': kotMap['served_at'],
          'delay_reason': kotMap['delay_reason'],
          'chef_name': kotMap['chef_name'],
          'priority': kotMap['priority'] ?? 'Normal',
          'estimated_time': kotMap['estimated_time'] ?? 15,
          'items': itemMaps,
        });
      }

      if (mounted) {
        setState(() {
          _kots = kots;
          _isLoading = false;
        });
        _checkForAutoDelays(kots);
      }
    } catch (e) {
      print('Error loading KOTs in Kitchen Screen: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateKOTStatus(int kotId, int orderId, String newStatus, {String? delayReason, String? chefName}) async {
    try {
      final db = await _dbHelper.database;
      final nowStr = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        final Map<String, dynamic> updateData = {'status': newStatus};
        if (newStatus == 'Cooking') {
          updateData['started_cooking_at'] = nowStr;
        } else if (newStatus == 'Ready') {
          updateData['ready_at'] = nowStr;
        } else if (newStatus == 'Served') {
          updateData['served_at'] = nowStr;
        } else if (newStatus == 'Delayed') {
          if (delayReason != null) {
            updateData['delay_reason'] = delayReason;
          }
        }

        if (chefName != null) {
          updateData['chef_name'] = chefName;
        }

        // Update KOT record
        await txn.update(
          'kot',
          updateData,
          where: 'id = ?',
          whereArgs: [kotId],
        );

        // Update KOT order items status
        await txn.update(
          'order_items',
          {'status': newStatus},
          where: 'kot_id = ?',
          whereArgs: [kotId],
        );

        // Determine parent order status
        final List<Map<String, dynamic>> siblingKots = await txn.query(
          'kot',
          columns: ['status'],
          where: 'order_id = ?',
          whereArgs: [orderId],
        );

        bool allServed = siblingKots.every((kot) => kot['status'] == 'Served');
        bool allReadyOrServed = siblingKots.every((kot) => kot['status'] == 'Ready' || kot['status'] == 'Served');
        bool hasCooking = siblingKots.any((kot) => kot['status'] == 'Cooking' || kot['status'] == 'Delayed');

        String orderStatus = 'Sent to Kitchen';
        if (allServed) {
          orderStatus = 'Served';
        } else if (allReadyOrServed) {
          orderStatus = 'Ready';
        } else if (hasCooking) {
          orderStatus = 'Preparing';
        }

        await txn.update(
          'orders',
          {'status': orderStatus},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        // Add to logs
        await txn.insert('order_status_logs', {
          'order_id': orderId,
          'status': newStatus,
          'changed_at': nowStr,
          'changed_by': chefName ?? 'Kitchen Staff',
          'notes': 'KOT #$kotId status changed to $newStatus.' + (delayReason != null ? ' Reason: $delayReason' : ''),
        });
      });

      // Broadcast changes instantly via WebSocket
      SyncService.instance.broadcastEvent('database_update', {});

      _loadKOTs(silent: true);
    } catch (e) {
      if (mounted) {

      }
    }
  }

  // Auto prompt a popup when a KOT has crossed its estimated time so the
  // kitchen can record the reason for the delay instead of it going unnoticed.
  void _checkForAutoDelays(List<Map<String, dynamic>> kots) {
    final now = DateTime.now();
    for (final kot in kots) {
      final status = kot['status'] as String? ?? 'Pending';
      if (status == 'Served' || status == 'Ready' || status == 'Delayed') continue;
      final delayReason = kot['delay_reason'] as String?;
      if (delayReason != null && delayReason.isNotEmpty) continue;
      final kotId = kot['id'] as int;
      if (_delayPromptedKotIds.contains(kotId)) continue;

      final created = DateTime.tryParse(kot['time'] as String) ?? now;
      final est = kot['estimated_time'] as int? ?? 15;
      if (now.difference(created).inMinutes >= est) {
        _delayPromptedKotIds.add(kotId);
        _delayPromptQueue.add(kotId);
      }
    }
    if (_delayPromptQueue.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _processDelayPromptQueue());
    }
  }

  Future<void> _processDelayPromptQueue() async {
    if (_delayDialogShowing) return;
    _delayDialogShowing = true;
    try {
      while (_delayPromptQueue.isNotEmpty && mounted) {
        final kotId = _delayPromptQueue.removeAt(0);
        final kotIndex = _kots.indexWhere((k) => k['id'] == kotId);
        if (kotIndex == -1) continue;
        final kot = _kots[kotIndex];
        await _showDelayDialog(kotId, kot['order_id'] as int);
        if (!mounted) return;
        await _loadKOTs(silent: true);
      }
    } finally {
      _delayDialogShowing = false;
    }
  }

  Future<void> _showDelayDialog(int kotId, int orderId) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Delay Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason for delay',
            hintText: 'e.g. Extra baking time, ingredients restock...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) {
                Navigator.pop(context);
                _updateKOTStatus(kotId, orderId, 'Delayed', delayReason: reason);
              }
            },
            child: const Text('Mark Delayed'),
          ),
        ],
      ),
    );
  }

  void _showAssignChefDialog(int kotId, int orderId, String currentChef) async {
    try {
      final db = await _dbHelper.database;
      final chefRecords = await db.query('users', where: "role = ? AND is_active = 1", whereArgs: ['Chef']);
      final List<String> chefNames = chefRecords.map((c) => c['name'] as String).toList();
      
      if (!mounted) return;

      String selectedChef = currentChef;
      String searchQuery = "";

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) {
            final filteredChefs = chefNames
                .where((name) => name.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.assignment_ind_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Assign Chef'),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search Chef',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: filteredChefs.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                searchQuery.isEmpty 
                                    ? 'No active chefs registered.\nGo to settings to add chef staff.' 
                                    : 'No matching chefs found.',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredChefs.length,
                              itemBuilder: (context, idx) {
                                final chef = filteredChefs[idx];
                                final isSelected = chef == selectedChef;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? AppColors.primary : Colors.grey.shade200,
                                    foregroundColor: isSelected ? Colors.white : Colors.black,
                                    child: Text(chef.substring(0, 1).toUpperCase()),
                                  ),
                                  title: Text(chef, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                  trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                                  onTap: () {
                                    setStateDialog(() {
                                      selectedChef = chef;
                                    });
                                  },
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateKOTStatus(kotId, orderId, 'Cooking', chefName: selectedChef.isEmpty ? 'Kitchen' : selectedChef);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: const Text('Assign & Prepare'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      print('Error assigning chef: $e');
    }
  }

  // Filter and sort the KOTs
  List<Map<String, dynamic>> _getFilteredKots() {
    List<Map<String, dynamic>> list = _kots;

    // Filter by Active vs History
    if (_showHistoryArchive) {
      list = list.where((kot) => kot['status'] == 'Served').toList();
    } else {
      list = list.where((kot) => kot['status'] != 'Served').toList();
    }

    // Filter by tab
    if (_selectedTab != 'All') {
      list = list.where((kot) {
        final status = kot['status'] as String;
        if (_selectedTab == 'Delayed') {
          return status == 'Delayed';
        }
        return status == _selectedTab;
      }).toList();
    }

    // Filter by kitchen section
    if (_selectedSection != 'All') {
      list = list.map((kot) {
        final items = List<Map<String, dynamic>>.from(kot['items']);
        final filteredItems = items.where((item) {
          final cat = (item['product_category'] as String? ?? 'General').toLowerCase();
          return cat == _selectedSection.toLowerCase();
        }).toList();
        
        return {
          ...kot,
          'items': filteredItems,
        };
      }).where((kot) {
        final items = kot['items'] as List;
        return items.isNotEmpty;
      }).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      list = list.where((kot) {
        final kotNum = (kot['kot_number'] as String).toLowerCase();
        final tabNum = (kot['table_number'] as String).toLowerCase();
        final customer = (kot['customer_name'] as String).toLowerCase();
        final query = _searchQuery.toLowerCase();
        return kotNum.contains(query) || tabNum.contains(query) || customer.contains(query);
      }).toList();
    }

    // Sorting logic
    if (_sortBy == 'Oldest First') {
      list.sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
    } else if (_sortBy == 'Priority') {
      // High priority first
      list.sort((a, b) {
        final ap = a['priority'] == 'High' ? 1 : 0;
        final bp = b['priority'] == 'High' ? 1 : 0;
        return bp.compareTo(ap);
      });
    } else if (_sortBy == 'Fastest Prep') {
      list.sort((a, b) => (a['estimated_time'] as int).compareTo(b['estimated_time'] as int));
    } else if (_sortBy == 'Table Orders') {
      list.sort((a, b) => (a['table_number'] as String).compareTo(b['table_number'] as String));
    }

    return list;
  }

  // Colors and preparation status calculations
  Color _getKOTColor(Map<String, dynamic> kot) {
    final status = kot['status'] as String;
    if (status == 'Ready') return Colors.blue.shade600;
    if (status == 'Served') return Colors.teal;
    if (status == 'Delayed') return Colors.red.shade600;

    final timeStr = kot['time'] as String;
    final created = DateTime.tryParse(timeStr) ?? DateTime.now();
    final elapsed = DateTime.now().difference(created).inMinutes;
    final est = kot['estimated_time'] as int;

    if (elapsed >= est) return Colors.red.shade600; // Delayed
    if (elapsed >= est - 3) return Colors.orange.shade600; // Near Delay
    return Colors.green.shade600; // On Time
  }

  String _getCountdownText(Map<String, dynamic> kot) {
    final status = kot['status'] as String;
    if (status == 'Ready') return 'Ready to Serve';
    if (status == 'Served') return 'Served';

    final timeStr = kot['time'] as String;
    final created = DateTime.tryParse(timeStr) ?? DateTime.now();
    final elapsed = DateTime.now().difference(created).inMinutes;
    final est = kot['estimated_time'] as int;

    if (elapsed >= est) {
      return 'Delayed by ${elapsed - est}m';
    }
    return '${est - elapsed} mins left';
  }

  @override
  Widget build(BuildContext context) {
    final filteredKots = _getFilteredKots();

    // Stats calculations
    final activeCount = _kots.where((k) => k['status'] != 'Served').length;
    final pendingCount = _kots.where((k) => k['status'] == 'Pending').length;
    final preparingCount = _kots.where((k) => k['status'] == 'Cooking').length;
    final delayedCount = _kots.where((k) {
      if (k['status'] == 'Delayed') return true;
      if (k['status'] == 'Served' || k['status'] == 'Ready') return false;
      final created = DateTime.tryParse(k['time'] as String) ?? DateTime.now();
      final elapsed = DateTime.now().difference(created).inMinutes;
      final est = k['estimated_time'] as int;
      return elapsed >= est;
    }).length;
    final readyCount = _kots.where((k) => k['status'] == 'Ready').length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Kitchen Display System (KDS)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade900 : Colors.white,
        foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.green, size: 10),
                    const SizedBox(width: 6),
                    Text(
                      'Live Workload: $activeCount Active',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadKOTs(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Live Analytics Dashboard Panel
                _buildLiveAnalyticsDashboard(
                  active: activeCount,
                  pending: pendingCount,
                  preparing: preparingCount,
                  delayed: delayedCount,
                  ready: readyCount,
                ),

                // Sliding Toggle between Active and Archive
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.run_circle_outlined),
                              label: Text('Active KOTs'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.archive_outlined),
                              label: Text('Completed KOTs Archive'),
                            ),
                          ],
                          selected: {_showHistoryArchive},
                          onSelectionChanged: (newSelection) {
                            setState(() {
                              _showHistoryArchive = newSelection.first;
                              _selectedTab = 'All';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Filters, Search and Sorting Bar
                _buildFilterAndSearchRow(),

                // Main Tickets Grid
                Expanded(
                  child: filteredKots.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'No matching KOT orders found',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisExtent: 380,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: filteredKots.length,
                          itemBuilder: (context, index) {
                            final kot = filteredKots[index];
                            return _buildKOTTicketCard(kot);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildLiveAnalyticsDashboard({
    required int active,
    required int pending,
    required int preparing,
    required int delayed,
    required int ready,
  }) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            _buildStatCard('Active Orders', '$active', Colors.blue, isMobile),
            _buildStatCard('Pending', '$pending', Colors.orange, isMobile),
            _buildStatCard('Preparing', '$preparing', Colors.amber, isMobile),
            _buildStatCard('Delayed', '$delayed', Colors.red, isMobile),
            _buildStatCard('Ready to Serve', '$ready', Colors.green, isMobile),
          ],
        );
      }),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, bool isMobile) {
    final width = isMobile ? 80.0 : 120.0;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFilterAndSearchRow() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        final searchBar = SizedBox(
          width: isMobile ? double.infinity : 220,
          height: 40,
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search Table or KOT...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        );

        final sortDropdown = DropdownButton<String>(
          value: _sortBy,
          underline: const SizedBox(),
          icon: const Icon(Icons.sort, size: 20),
          items: ['Oldest First', 'Priority', 'Fastest Prep', 'Table Orders']
              .map((val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _sortBy = val);
          },
        );

        final sectionDropdown = DropdownButton<String>(
          value: _selectedSection,
          underline: const SizedBox(),
          icon: const Icon(Icons.flatware, size: 20, color: AppColors.primary),
          items: ['All', 'Chinese', 'Tandoor', 'Fast Food', 'Main Course', 'Dessert', 'Beverages']
              .map((val) => DropdownMenuItem(value: val, child: Text(val == 'All' ? 'All Sections' : '$val Section', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedSection = val);
          },
        );

        final filtersSegment = _showHistoryArchive
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Pending', 'Cooking', 'Ready', 'Delayed'].map((tab) {
                    final isSelected = _selectedTab == tab;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(tab == 'Cooking' ? 'Preparing' : tab),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _selectedTab = tab);
                        },
                      ),
                    );
                  }).toList(),
                ),
              );

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchBar,
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  sectionDropdown,
                  sortDropdown,
                ],
              ),
              const SizedBox(height: 4),
              filtersSegment,
            ],
          );
        }

        return Row(
          children: [
            filtersSegment,
            const SizedBox(width: 16),
            sectionDropdown,
            const Spacer(),
            sortDropdown,
            const SizedBox(width: 16),
            searchBar,
          ],
        );
      }),
    );
  }

  Widget _buildKOTTicketCard(Map<String, dynamic> kot) {
    final int kotId = kot['id'];
    final int orderId = kot['order_id'];
    final String kotNumber = kot['kot_number'];
    final String tableNumber = kot['table_number'];
    final String notes = kot['notes'] as String;
    final String status = kot['status'];
    final String timeStr = kot['time'] as String;
    final createdTime = DateTime.tryParse(timeStr) ?? DateTime.now();
    final items = kot['items'] as List<Map<String, dynamic>>;
    final priority = kot['priority'] as String;
    final chefName = kot['chef_name'] as String?;
    final delayReason = kot['delay_reason'] as String?;

    final statusColor = _getKOTColor(kot);
    final timeBadgeText = _getCountdownText(kot);

    // Calculate total KOT preparation estimation sum
    int totalPrepSum = 0;
    for (var it in items) {
      final pPrep = it['prep_time'] as int? ?? 5;
      final pCook = it['cook_time'] as int? ?? 10;
      totalPrepSum += (pPrep + pCook) * (it['quantity'] as int);
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: priority == 'High' 
              ? Colors.redAccent.shade100 
              : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200),
          width: priority == 'High' ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KOT Card Header with color indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Live Status Indicator Circle
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tableNumber != 'Takeaway' ? 'Table $tableNumber' : 'Takeaway / Parcel',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                // Priority Badge
                if (priority == 'High')
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                    child: const Text('HIGH PRIORITY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                // Countdown Timer text
                Text(
                  timeBadgeText,
                  style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ),

          // Details Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  kotNumber,
                  style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  DateFormat('hh:mm a').format(createdTime),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #$orderId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('Est: ${kot['estimated_time']}m (Sum: ${totalPrepSum}m)', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ],
            ),
          ),
          
          if (chefName != null && chefName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Chef: $chefName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ],
              ),
            ),

          if (delayReason != null && delayReason.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Delay: $delayReason',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 12),

          // Items scroll list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final it = items[idx];
                final iPrep = it['prep_time'] as int? ?? 5;
                final iCook = it['cook_time'] as int? ?? 10;
                final singleEst = iPrep + iCook;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${it['quantity']}x',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it['product_name'],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (it['item_notes'] != null && (it['item_notes'] as String).isNotEmpty)
                              Text(
                                '* ${it['item_notes']}',
                                style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${singleEst}m',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          if (notes.isNotEmpty) ...[
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Text(
                'KOT Notes: $notes',
                style: const TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const Divider(height: 1),

          // Chef Interaction Panel
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade900 : Colors.grey.shade100,
            child: Row(
              children: [
                // Delay Alert Trigger
                if (status != 'Served' && status != 'Ready')
                  IconButton(
                    icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    // tooltip disabled,
                    onPressed: () => _showDelayDialog(kotId, orderId),
                  ),

                // Chef Assignment trigger
                if (status == 'Pending')
                  IconButton(
                    icon: const Icon(Icons.assignment_ind_outlined, color: Colors.blue),
                    // tooltip disabled,
                    onPressed: () => _showAssignChefDialog(kotId, orderId, chefName ?? ''),
                  ),

                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (status == 'Pending') {
                        _updateKOTStatus(kotId, orderId, 'Cooking');
                      } else if (status == 'Cooking' || status == 'Delayed') {
                        _updateKOTStatus(kotId, orderId, 'Ready');
                      } else if (status == 'Ready') {
                        _updateKOTStatus(kotId, orderId, 'Served');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      status == 'Pending'
                          ? 'Start Preparing'
                          : status == 'Cooking' || status == 'Delayed'
                              ? 'Mark Ready'
                              : status == 'Ready'
                                  ? 'Mark Served'
                                  : 'Served Complete',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
