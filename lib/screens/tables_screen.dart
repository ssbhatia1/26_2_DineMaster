import 'dart:async';
import 'package:nexodine/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../repositories/table_repository.dart';
import '../models/table_model.dart';
import '../core/database/database_helper.dart';
import '../widgets/searchable_dropdown.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final TableRepository _tableRepository = TableRepository();
  List<Map<String, dynamic>> _enrichedTables = [];
  List<Map<String, dynamic>> _bookingsList = [];
  List<Map<String, dynamic>> _heldOrdersList = [];
  List<Map<String, dynamic>> _waiters = [];
  bool _isLoading = true;

  // Filters & Search
  String _searchQuery = '';
  String _selectedSection = 'All';
  String _statusFilter = 'All';
  String _capacityFilter = 'All';
  String _sortBy = 'Table Number';
  DateTime _selectedGridDate = DateTime.now();

  List<String> _sections = ['All'];
  List<String> _tableTypes = ['Standard Table'];

  static const List<String> _allStatuses = [
    'All',
    'Available',
    'Occupied',
    'Reserved',
    'Ordering',
    'Preparing',
    'Bill Requested',
    'Payment Pending',
    'Paid',
    'Cleaning',
    'Out of Service',
  ];

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadWaiters();
  }

  Future<void> _loadWaiters() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final waiters = await db.query(
        'users',
        where: 'role = ? AND is_active = 1',
        whereArgs: ['Waiter'],
        orderBy: 'name ASC',
      );
      if (!mounted) return;
      setState(() => _waiters = waiters);
    } catch (e) {
      debugPrint('Error loading waiters: $e');
    }
  }

  Future<void> _loadTables() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;

      // Load dynamic sections and table types
      final sectionMaps = await db.query('table_sections', where: 'restaurant_id = ?', whereArgs: [restaurantId]);
      final typeMaps = await db.query('table_types', where: 'restaurant_id = ?', whereArgs: [restaurantId]);

      List<String> loadedSections = ['All'];
      loadedSections.addAll(sectionMaps.map((m) => m['name'] as String));
      if (loadedSections.length == 1) loadedSections.add('Main Hall'); // Fallback

      List<String> loadedTypes = [];
      loadedTypes.addAll(typeMaps.map((m) => m['name'] as String));
      if (loadedTypes.isEmpty) loadedTypes.add('Standard Table'); // Fallback

      // Load all tables for current restaurant
      final List<Map<String, dynamic>> tableMaps = await db.query(
        'tables',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
      );

      List<Map<String, dynamic>> enrichedTables = [];

      for (var tMap in tableMaps) {
        final tableId = tMap['id'] as int;

        // Find active booking for this table
        final List<Map<String, dynamic>> bookingMaps = await db.query(
          'bookings',
          where: 'table_id = ? AND status = ? AND restaurant_id = ?',
          whereArgs: [tableId, 'Confirmed', restaurantId],
          orderBy: 'booking_time ASC',
          limit: 1,
        );

        // Find active order (Received, Preparing, Ready, Served, Billing Pending, Held)
        final List<Map<String, dynamic>> orderMaps = await db.query(
          'orders',
          where: 'table_id = ? AND status IN (?, ?, ?, ?, ?, ?) AND restaurant_id = ?',
          whereArgs: [
            tableId,
            'Received',
            'Preparing',
            'Ready',
            'Served',
            'Billing Pending',
            'Held',
            restaurantId,
          ],
          orderBy: 'id DESC',
          limit: 1,
        );

        Map<String, dynamic>? activeBooking = bookingMaps.isNotEmpty ? bookingMaps.first : null;
        Map<String, dynamic>? activeOrder = orderMaps.isNotEmpty ? orderMaps.first : null;

        // Count items in active order
        int orderItemsCount = 0;
        if (activeOrder != null) {
          final items = await db.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [activeOrder['id']],
          );
          orderItemsCount = items.fold(0, (sum, it) => sum + (it['quantity'] as int? ?? 1));
        }

        enrichedTables.add({
          'table': TableModel.fromMap(tMap),
          'active_booking': activeBooking,
          'active_order': activeOrder,
          'order_items_count': orderItemsCount,
        });
      }

      // Also load all booked tables list
      final List<Map<String, dynamic>> allBookings = await db.rawQuery('''
        SELECT b.*, t.table_number 
        FROM bookings b
        JOIN tables t ON b.table_id = t.id
        WHERE b.status = 'Confirmed' AND b.restaurant_id = ?
        ORDER BY b.booking_time ASC
      ''', [restaurantId]);

      // Also load all held orders list
      final List<Map<String, dynamic>> allHeldOrders = await db.rawQuery('''
        SELECT o.*, t.table_number 
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.status = 'Held' AND o.restaurant_id = ?
        ORDER BY o.order_time DESC
      ''', [restaurantId]);

      if (!mounted) return;
      setState(() {
        _sections = loadedSections;
        _tableTypes = loadedTypes;
        _enrichedTables = enrichedTables;
        _bookingsList = allBookings;
        _heldOrdersList = allHeldOrders;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading tables: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Filtered & Sorted Table List
  List<Map<String, dynamic>> get _filteredTables {
    var list = _enrichedTables.where((item) {
      final table = item['table'] as TableModel;
      final activeOrder = item['active_order'] as Map<String, dynamic>?;
      final isHeld = activeOrder != null && activeOrder['status'] == 'Held';

      // 1. Search Query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesNum = table.tableNumber.toLowerCase().contains(q);
        final matchesName = table.name?.toLowerCase().contains(q) ?? false;
        final matchesNotes = table.notes?.toLowerCase().contains(q) ?? false;
        final matchesSection = table.section.toLowerCase().contains(q);
        if (!matchesNum && !matchesName && !matchesNotes && !matchesSection) return false;
      }

      // 2. Section Filter
      if (_selectedSection != 'All' && table.section != _selectedSection) {
        return false;
      }

      // 3. Status Filter
      if (_statusFilter != 'All') {
        if (_statusFilter == 'Held') {
          if (!isHeld) return false;
        } else if (_statusFilter == 'Occupied') {
          if (table.status != 'Occupied' && activeOrder == null) return false;
        } else if (_statusFilter == 'Available') {
          if (table.status != 'Available' || activeOrder != null) return false;
        } else if (table.status != _statusFilter) {
          return false;
        }
      }

      // 4. Capacity Filter
      if (_capacityFilter == '2 Seats' && table.capacity > 2) return false;
      if (_capacityFilter == '4 Seats' && (table.capacity < 3 || table.capacity > 4)) return false;
      if (_capacityFilter == '6+ Seats' && table.capacity < 6) return false;

      return true;
    }).toList();

    // Sorting
    list.sort((a, b) {
      final tA = a['table'] as TableModel;
      final tB = b['table'] as TableModel;

      switch (_sortBy) {
        case 'Capacity':
          return tB.capacity.compareTo(tA.capacity);
        case 'Status':
          return tA.status.compareTo(tB.status);
        case 'Section':
          return tA.section.compareTo(tB.section);
        case 'Table Number':
        default:
          return tA.tableNumber.compareTo(tB.tableNumber);
      }
    });

    return list;
  }

  // Quick Stats KPI computation
  Map<String, int> get _statusCounts {
    int total = _enrichedTables.length;
    int available = 0;
    int occupied = 0;
    int reserved = 0;
    int preparing = 0;
    int billing = 0;
    int cleaning = 0;

    for (var item in _enrichedTables) {
      final table = item['table'] as TableModel;
      final activeOrder = item['active_order'] as Map<String, dynamic>?;

      if (activeOrder != null) {
        final st = activeOrder['status'];
        if (st == 'Preparing' || st == 'Received') {
          preparing++;
        } else if (st == 'Billing Pending') {
          billing++;
        }
      }

      switch (table.status) {
        case 'Available':
          if (activeOrder == null) available++;
          break;
        case 'Occupied':
          occupied++;
          break;
        case 'Reserved':
          reserved++;
          break;
        case 'Cleaning':
          cleaning++;
          break;
        case 'Bill Requested':
        case 'Payment Pending':
          billing++;
          break;
        case 'Preparing':
          preparing++;
          break;
      }
    }

    return {
      'Total': total,
      'Available': available,
      'Occupied': occupied,
      'In Kitchen': preparing,
      'Billing': billing,
      'Reserved': reserved,
      'Cleaning': cleaning,
    };
  }

  // Color & Icon Scheme by Status
  Color _getStatusColor(String status, bool isHeld) {
    if (isHeld) return Colors.purple;
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
        return const Color(0xFFF57C00); // Bright Orange
      case 'Bill Requested':
        return const Color(0xFFF9A825); // Gold / Yellow
      case 'Payment Pending':
        return const Color(0xFFD84315); // Deep Amber
      case 'Paid':
        return const Color(0xFF00897B); // Teal
      case 'Cleaning':
        return const Color(0xFF0288D1); // Cyan Blue
      case 'Out of Service':
        return const Color(0xFF546E7A); // Slate Grey
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Available':
        return Icons.check_circle_outline;
      case 'Occupied':
        return Icons.people_alt;
      case 'Reserved':
        return Icons.bookmark_added_outlined;
      case 'Ordering':
        return Icons.edit_note;
      case 'Preparing':
        return Icons.outdoor_grill_outlined;
      case 'Bill Requested':
        return Icons.receipt_long;
      case 'Payment Pending':
        return Icons.payments_outlined;
      case 'Paid':
        return Icons.check_circle;
      case 'Cleaning':
        return Icons.cleaning_services_outlined;
      case 'Out of Service':
        return Icons.block_outlined;
      default:
        return Icons.table_bar;
    }
  }

  // Format Elapsed Occupied Time
  String _getOccupiedDuration(String? orderTime) {
    if (orderTime == null) return '';
    try {
      final dt = DateTime.parse(orderTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inHours > 0) {
        return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
      }
      return '${diff.inMinutes} mins ago';
    } catch (_) {
      return '';
    }
  }

  // Table Configuration Dialog (Add & Edit Table)
  void _showTableConfigDialog([TableModel? existingTable]) {
    final isEditing = existingTable != null;
    final numberCtrl = TextEditingController(text: existingTable?.tableNumber ?? '');
    final nameCtrl = TextEditingController(text: existingTable?.name ?? '');
    final capacityCtrl = TextEditingController(text: (existingTable?.capacity ?? 4).toString());
    final notesCtrl = TextEditingController(text: existingTable?.notes ?? '');
    String section = existingTable?.section ?? 'Main Hall';
    String tableType = existingTable?.tableType ?? 'Standard Table';
    String status = existingTable?.status ?? 'Available';
    bool isActive = existingTable?.isActive ?? true;
    bool isReservable = existingTable?.isReservable ?? true;
    int? selectedWaiterId = existingTable?.waiterId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) {
          final currentWaiter = selectedWaiterId != null
              ? _waiters.firstWhere((w) => w['id'] == selectedWaiterId, orElse: () => {})
              : null;
          final cleanWaiter = currentWaiter != null && currentWaiter.isNotEmpty ? currentWaiter : null;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(
                    isEditing ? Icons.edit_note : Icons.add_business_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEditing ? 'Configure Table ${existingTable.tableNumber}' : 'Add New Restaurant Table',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: numberCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Table Number *',
                              hintText: 'e.g. T-01, B-12',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Table Name / Alias',
                              hintText: 'e.g. Window Booth, Corner Table',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: capacityCtrl,
                            keyboardType: TextInputType.number,
                            enabled: !isEditing || (existingTable?.status == 'Available'),
                            decoration: InputDecoration(
                              labelText: (!isEditing || (existingTable?.status == 'Available')) ? 'Seating Capacity *' : 'Capacity Locked (Active Order)',
                              prefixIcon: const Icon(Icons.chair_alt),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: section,
                            items: _sections
                                .where((s) => s != 'All')
                                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (val) => setDlgState(() => section = val!),
                            decoration: const InputDecoration(
                              labelText: 'Section / Dining Area',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: tableType,
                            items: _tableTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) => setDlgState(() => tableType = val!),
                            decoration: const InputDecoration(
                              labelText: 'Table Type / Shape',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: status,
                            items: _allStatuses
                                .where((s) => s != 'All')
                                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (val) => setDlgState(() => status = val!),
                            decoration: const InputDecoration(
                              labelText: 'Table Status',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SearchableDropdown<Map<String, dynamic>>(
                      items: _waiters,
                      value: cleanWaiter,
                      labelText: 'Default Assigned Waiter',
                      hintText: 'Select or search waiter...',
                      itemToString: (w) => w['name'] as String,
                      filterFn: (w, query) => (w['name'] as String).toLowerCase().contains(query.toLowerCase()),
                      onChanged: (val) => setDlgState(() => selectedWaiterId = val?['id']),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Table Notes / Location Specifics',
                        hintText: 'e.g. Near AC, power outlet available, quiet area...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Active Table', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Visible on POS layout', style: TextStyle(fontSize: 11)),
                            value: isActive,
                            onChanged: (val) => setDlgState(() => isActive = val),
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Reservable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Available for booking', style: TextStyle(fontSize: 11)),
                            value: isReservable,
                            onChanged: (val) => setDlgState(() => isReservable = val),
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isEditing)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmDeleteTable(existingTable.id!, existingTable.tableNumber);
                  },
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.save, size: 18),
                label: Text(isEditing ? 'Update Table' : 'Create Table'),
                onPressed: () async {
                  final num = numberCtrl.text.trim();
                  final cap = int.tryParse(capacityCtrl.text.trim()) ?? 0;

                  if (num.isEmpty || cap <= 0) {
                    if(false) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter valid table number and seating capacity')),
                    );
                    return;
                  }

                  final updated = TableModel(
                    id: existingTable?.id,
                    tableNumber: num,
                    name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
                    capacity: cap,
                    status: status,
                    section: section,
                    tableType: tableType,
                    isActive: isActive,
                    isReservable: isReservable,
                    notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                    waiterId: selectedWaiterId,
                    restaurantId: DatabaseHelper.currentRestaurantId,
                  );

                  try {
                    if (isEditing) {
                      await _tableRepository.updateTable(updated);
                    } else {
                      await _tableRepository.addTable(updated);
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      _loadTables();
                      if(false) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Table $num saved successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      if(false) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error saving table: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // Quick Order View Modal
  void _showOrderDetailsSheet(TableModel table, Map<String, dynamic> activeOrder) async {
    final db = await DatabaseHelper.instance.database;
    final orderId = activeOrder['id'] as int;

    final items = await db.rawQuery('''
      SELECT oi.*, p.name as product_name, p.category, p.is_veg
      FROM order_items oi
      JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = ?
    ''', [orderId]);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final total = (activeOrder['total_amount'] as num?)?.toDouble() ?? 0.0;
        final guest = activeOrder['customer_name'] ?? 'Guest';
        final orderTaker = activeOrder['order_taker_name'] ?? 'Staff';
        final timeStr = activeOrder['order_time'] ?? '';

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${activeOrder['id']} • ${table.displayName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Guest: $guest • Taken by: $orderTaker • ${_getOccupiedDuration(timeStr)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Chip(
                    label: Text(activeOrder['status'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    backgroundColor: _getStatusColor(activeOrder['status'], false),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text('Ordered Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(child: Text('No items recorded in this order')),
                )
              else
                ...items.map((it) {
                  final pName = it['product_name'] as String? ?? 'Item';
                  final qty = it['quantity'] as int? ?? 1;
                  final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                  final notes = it['notes'] as String?;
                  final itStatus = it['status'] as String? ?? 'Pending';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$qty x ', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (notes != null && notes.isNotEmpty)
                                Text(
                                  '📝 $notes',
                                  style: TextStyle(fontSize: 11, color: AppColors.primaryMaterialColor[700]!, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(itStatus, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                        ),
                        const SizedBox(width: 12),
                        Text('₹${(price * qty).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Bill Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer Table'),
                      onPressed: () {
                        Navigator.pop(context);
                        _showTransferDialog(table, orderId);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Open POS / Add Items'),
                      onPressed: () {
                        Navigator.pop(context);
                        context.go('/dashboard/pos?tableId=${table.id}&reopenOrderId=$orderId');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Transfer Table Dialog
  void _showTransferDialog(TableModel sourceTable, int orderId) {
    TableModel? destinationTable;

    final availableTables = _enrichedTables
        .map((e) => e['table'] as TableModel)
        .where((t) => t.id != sourceTable.id && (t.status == 'Available' || t.status == 'Cleaning'))
        .toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Transfer Table ${sourceTable.tableNumber}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Table: ${sourceTable.displayName}'),
              const SizedBox(height: 16),
              const Text('Select Destination Table:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (availableTables.isEmpty)
                const Text('No other available tables at this moment.', style: TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<TableModel>(
                  value: destinationTable,
                  hint: const Text('Choose Target Table'),
                  items: availableTables.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text('${t.displayName} (${t.capacity} seats • ${t.section})'),
                    );
                  }).toList(),
                  onChanged: (val) => setDlgState(() => destinationTable = val),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: destinationTable == null
                  ? null
                  : () async {
                      final db = await DatabaseHelper.instance.database;

                      // Move order to destination table
                      await db.update(
                        'orders',
                        {'table_id': destinationTable!.id},
                        where: 'id = ?',
                        whereArgs: [orderId],
                      );

                      // Update destination table status to Occupied
                      await _tableRepository.updateTableStatus(destinationTable!.id!, 'Occupied');

                      // Mark source table as Cleaning or Available
                      await _tableRepository.updateTableStatus(sourceTable.id!, 'Cleaning');

                      if (mounted) {
                        Navigator.pop(context);
                        _loadTables();
                        if(false) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Order transferred to ${destinationTable!.tableNumber}! Table ${sourceTable.tableNumber} set to Cleaning.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
              child: const Text('Confirm Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  // Reservation Dialog
  void _showReservationDialog(TableModel table, [DateTime? initialDate]) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final guestsCtrl = TextEditingController(text: '${table.capacity}');
    final notesCtrl = TextEditingController();
    DateTime date = initialDate ?? DateTime.now();
    TimeOfDay time = initialDate != null ? TimeOfDay.fromDateTime(initialDate) : TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.bookmark_added_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Reserve ${table.displayName}'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Customer / Guest Name *', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: guestsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Guest Count', prefixIcon: Icon(Icons.people_outline)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(DateFormat('dd MMM yyyy').format(date)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 60)),
                          );
                          if (picked != null) setDlgState(() => date = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(time.format(context)),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: time);
                          if (picked != null) setDlgState(() => time = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Reservation Notes (e.g. Birthday celebration)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) {
                  if(false) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter customer name')));
                  return;
                }

                final bookingDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                ).toIso8601String();

                final db = await DatabaseHelper.instance.database;
                await db.insert('bookings', {
                  'table_id': table.id,
                  'customer_name': nameCtrl.text.trim(),
                  'customer_phone': phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                  'guest_count': int.tryParse(guestsCtrl.text.trim()) ?? table.capacity,
                  'booking_time': bookingDateTime,
                  'status': 'Confirmed',
                  'notes': notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  'restaurant_id': DatabaseHelper.currentRestaurantId,
                });

                // Update table status to Reserved
                await _tableRepository.updateTableStatus(table.id!, 'Reserved');

                if (mounted) {
                  Navigator.pop(context);
                  _loadTables();
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${table.displayName} reserved for ${nameCtrl.text.trim()}!'), backgroundColor: Colors.green),
                  );
                }
              },
              child: const Text('Confirm Reservation'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTable(int id, String number) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text('Are you sure you want to delete table "$number"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await _tableRepository.deleteTable(id);
              if (mounted) {
                Navigator.pop(context);
                _loadTables();
                if(false) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Table "$number" deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Quick Status Transition
  Future<void> _updateStatus(TableModel table, String newStatus) async {
    await _tableRepository.updateTableStatus(table.id!, newStatus);
    _loadTables();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Restaurant Table Management'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              // tooltip disabled,
              onPressed: _loadTables,
            ),
            IconButton(
              icon: const Icon(Icons.add_business),
              // tooltip disabled,
              onPressed: () => _showTableConfigDialog(),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(icon: Icon(Icons.grid_view), text: 'Table Layout Grid'),
              Tab(icon: Icon(Icons.calendar_view_day), text: 'Booking Time Grid'),
              Tab(icon: Icon(Icons.bookmark_added_outlined), text: 'Booked / Reserved'),
              Tab(icon: Icon(Icons.pause_circle_outline), text: 'Active Hold Orders'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildTableLayoutGridTab(),
                  _buildBookingTimeGridTab(),
                  _buildBookedTablesTab(),
                  _buildHoldOrdersTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fab_add_table',
          onPressed: () => _showTableConfigDialog(),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add Table'),
        ),
      ),
    );
  }

  // TAB 1: Visual Table Layout Grid (Flagship Dashboard)
  Widget _buildTableLayoutGridTab() {
    final filtered = _filteredTables;
    final counts = _statusCounts;

    return Column(
      children: [
        // 1. Real-Time KPI Stats Overview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.grey.shade50,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKpiCard('Total Tables', '${counts['Total']}', Icons.table_bar, Colors.grey.shade800, 'All'),
                const SizedBox(width: 8),
                _buildKpiCard('Available', '${counts['Available']}', Icons.check_circle_outline, const Color(0xFF2E7D32), 'Available'),
                const SizedBox(width: 8),
                _buildKpiCard('Occupied', '${counts['Occupied']}', Icons.people, const Color(0xFF1565C0), 'Occupied'),
                const SizedBox(width: 8),
                _buildKpiCard('In Kitchen', '${counts['In Kitchen']}', Icons.outdoor_grill_outlined, const Color(0xFFE65100), 'Preparing'),
                const SizedBox(width: 8),
                _buildKpiCard('Billing', '${counts['Billing']}', Icons.receipt_long, const Color(0xFFF9A825), 'Bill Requested'),
                const SizedBox(width: 8),
                _buildKpiCard('Cleaning', '${counts['Cleaning']}', Icons.cleaning_services_outlined, const Color(0xFF0288D1), 'Cleaning'),
                const SizedBox(width: 8),
                _buildKpiCard('Reserved', '${counts['Reserved']}', Icons.bookmark_added_outlined, const Color(0xFF7B1FA2), 'Reserved'),
              ],
            ),
          ),
        ),

        // 2. Multi-Filter & Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by table #, name, section, or notes...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedSection,
                    underline: const SizedBox(),
                    items: _sections.map((s) => DropdownMenuItem(value: s, child: Text('Area: $s'))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedSection = val);
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _capacityFilter,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('Cap: All')),
                      DropdownMenuItem(value: '2 Seats', child: Text('Cap: 2 Seats')),
                      DropdownMenuItem(value: '4 Seats', child: Text('Cap: 4 Seats')),
                      DropdownMenuItem(value: '6+ Seats', child: Text('Cap: 6+ Seats')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _capacityFilter = val);
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _sortBy,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'Table Number', child: Text('Sort: Number')),
                      DropdownMenuItem(value: 'Capacity', child: Text('Sort: Capacity')),
                      DropdownMenuItem(value: 'Status', child: Text('Sort: Status')),
                      DropdownMenuItem(value: 'Section', child: Text('Sort: Area')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _sortBy = val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Grid of Table Cards
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.table_restaurant_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        'No tables match the selected filters',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _selectedSection = 'All';
                            _statusFilter = 'All';
                            _capacityFilter = 'All';
                          });
                        },
                        child: const Text('Reset Filters'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 260,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildTableCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String count, IconData icon, Color color, String filterKey) {
    final isSelected = _statusFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          _statusFilter = isSelected ? 'All' : filterKey;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(35) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Individual Table Card
  Widget _buildTableCard(Map<String, dynamic> item) {
    final table = item['table'] as TableModel;
    final activeOrder = item['active_order'] as Map<String, dynamic>?;
    final activeBooking = item['active_booking'] as Map<String, dynamic>?;
    final orderItemsCount = item['order_items_count'] as int? ?? 0;

    // Merged group info: tables merged into this table, and table this is merged into.
    final mergedMembers = _enrichedTables
        .where((e) => (e['table'] as TableModel).mergedWithId == table.id)
        .map((e) => e['table'] as TableModel)
        .toList();
    String? mergedIntoNumber;
    if (table.mergedWithId != null) {
      for (final e in _enrichedTables) {
        if ((e['table'] as TableModel).id == table.mergedWithId) {
          mergedIntoNumber = (e['table'] as TableModel).tableNumber;
          break;
        }
      }
    }
    final isMergedMember = table.mergedWithId != null && mergedMembers.isEmpty;

    final isHeld = activeOrder != null && activeOrder['status'] == 'Held';
    final hasActiveOrder = activeOrder != null && !isHeld;

    // Determine current display status
    String displayStatus = table.status;
    if (isHeld) {
      displayStatus = 'Hold Order';
    } else if (hasActiveOrder) {
      displayStatus = activeOrder['status'] ?? table.status;
    }

    final statusColor = _getStatusColor(displayStatus, isHeld);
    final statusIcon = _getStatusIcon(displayStatus);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withAlpha(120), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: statusColor.withAlpha(25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: statusColor,
                      child: Icon(statusIcon, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      table.tableNumber,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: statusColor),
                    ),
                    if (table.name != null && table.name!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${table.name})',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    displayStatus.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Body Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Merged Group Indicator
                  if (mergedMembers.isNotEmpty || isMergedMember) ...[
                    Row(
                      children: [
                        Icon(
                          mergedMembers.isNotEmpty ? Icons.merge_type : Icons.call_split,
                          size: 14,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            mergedMembers.isNotEmpty
                                ? 'Merged: ${[table, ...mergedMembers].map((t) => t.tableNumber).join(' + ')} • Capacity: ${table.capacity + mergedMembers.fold<int>(0, (s, t) => s + t.capacity)}'
                                : 'Part of merged group: Table ${mergedIntoNumber ?? ''}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Badges: Section & Capacity & Type
                  Row(
                    children: [
                      _buildChip(table.section, Icons.location_on_outlined),
                      const SizedBox(width: 6),
                      _buildChip('${table.capacity} Seats', Icons.chair_alt),
                      const SizedBox(width: 6),
                      _buildChip(table.tableType, Icons.table_restaurant),
                    ],
                  ),
                  const Spacer(),

                  // Dynamic Context Information
                  if (hasActiveOrder) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #${activeOrder['id']} • $orderItemsCount items',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Guest: ${activeOrder['customer_name'] ?? 'Guest'} • ${_getOccupiedDuration(activeOrder['order_time'])}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        Text(
                          '₹${(activeOrder['total_amount'] as num?)?.toStringAsFixed(2) ?? "0.00"}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ] else if (isHeld) ...[
                    Text(
                      'Held Order #${activeOrder['id']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 13),
                    ),
                    Text(
                      'Total: ₹${activeOrder['total_amount']} • ${_getOccupiedDuration(activeOrder['order_time'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ] else if (activeBooking != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.bookmark_added, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Booked: ${activeBooking['customer_name']} (${activeBooking['guest_count']} guests)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Time: ${DateFormat('dd MMM hh:mm a').format(DateTime.parse(activeBooking['booking_time']))}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ] else if (table.status == 'Cleaning') ...[
                    Row(
                      children: [
                        const Icon(Icons.cleaning_services, size: 16, color: Colors.cyan),
                        const SizedBox(width: 6),
                        const Text(
                          'Table is currently being sanitized',
                          style: TextStyle(fontSize: 12, color: Colors.cyan, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      'Ready for new party (${table.capacity} guests)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Contextual Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Configure / Menu
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.grey),
                  // tooltip disabled,
                  onPressed: () => _showTableConfigDialog(table),
                ),

                // Context Actions
                if (isMergedMember)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      'Order taken on merged Table $mergedIntoNumber',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                    ),
                  )
                else if (table.status == 'Available' && !hasActiveOrder && !isHeld) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.bookmark_outline, size: 14),
                    label: const Text('Reserve', style: TextStyle(fontSize: 12)),
                    onPressed: () => _showReservationDialog(table),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      context.go('/dashboard/waiter_order?tableId=${table.id}');
                    },
                  ),
                ] else if (hasActiveOrder) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () => _showOrderDetailsSheet(table, activeOrder),
                    child: const Text('View Order', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.point_of_sale, size: 14),
                    label: const Text('Open Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      context.go('/dashboard/waiter_order?tableId=${table.id}');
                    },
                  ),
                ] else if (isHeld) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 14),
                    label: const Text('Resume Order', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      context.go('/dashboard/waiter_order?tableId=${table.id}');
                    },
                  ),
                ] else if (table.status == 'Cleaning') ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0288D1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark Available', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _updateStatus(table, 'Available'),
                  ),
                ] else if (table.status == 'Reserved') ...[
                  OutlinedButton(
                    onPressed: () => _updateStatus(table, 'Available'),
                    child: const Text('Cancel Booking', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => context.go('/dashboard/waiter_order?tableId=${table.id}'),
                    child: const Text('Start Order', style: TextStyle(fontSize: 12)),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () => _updateStatus(table, 'Available'),
                    child: const Text('Mark Available', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // TAB 2: Booking Time Grid (Hourly Slot View)
  Widget _buildBookingTimeGridTab() {
    final startHour = 10; // 10 AM
    final endHour = 23; // 11 PM
    final timeSlots = List.generate(endHour - startHour + 1, (index) => startHour + index);

    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedGridDate);
    final bookingsForDay = _bookingsList.where((b) {
      final bTime = b['booking_time'] as String;
      return bTime.startsWith(selectedDateStr);
    }).toList();

    return Column(
      children: [
        // Date Selector Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                DateFormat('EEE, dd MMMM yyyy').format(_selectedGridDate),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () {
                  setState(() => _selectedGridDate = _selectedGridDate.subtract(const Duration(days: 1)));
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text('Select Date'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedGridDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (picked != null) setState(() => _selectedGridDate = picked);
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {
                  setState(() => _selectedGridDate = _selectedGridDate.add(const Duration(days: 1)));
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Grid
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                columns: [
                  const DataColumn(label: Text('Table #', style: TextStyle(fontWeight: FontWeight.bold))),
                  ...timeSlots.map((h) {
                    final display = h > 12 ? '${h - 12} PM' : (h == 12 ? '12 PM' : '$h AM');
                    final now = DateTime.now();
                    final isCurrentHour = now.hour == h && _selectedGridDate.day == now.day && _selectedGridDate.month == now.month && _selectedGridDate.year == now.year;
                    
                    return DataColumn(
                      label: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: isCurrentHour ? BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)) : null,
                        child: Text(display, style: TextStyle(fontWeight: FontWeight.bold, color: isCurrentHour ? Colors.blue.shade900 : null)),
                      )
                    );
                  }),
                ],
                rows: _enrichedTables.map((item) {
                  final table = item['table'] as TableModel;
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          children: [
                            const Icon(Icons.table_bar, size: 16, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(table.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ...timeSlots.map((h) {
                        final booking = bookingsForDay.firstWhere((b) {
                          if (b['table_id'] != table.id) return false;
                          final bTime = DateTime.parse(b['booking_time']);
                          return bTime.hour == h;
                        }, orElse: () => {});

                        final isBooked = booking.isNotEmpty;
                        final now = DateTime.now();
                        final isCurrentHour = now.hour == h && _selectedGridDate.day == now.day && _selectedGridDate.month == now.month && _selectedGridDate.year == now.year;

                        return DataCell(
                          Container(
                            color: isCurrentHour ? Colors.blue.withValues(alpha: 0.05) : null,
                            child: isBooked
                                ? Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade800, width: 2),
                                    ),
                                    child: Text(
                                      booking['customer_name'] ?? 'Booked',
                                      style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : InkWell(
                                    onTap: () {
                                      final selectedDateTime = DateTime(_selectedGridDate.year, _selectedGridDate.month, _selectedGridDate.day, h, 0);
                                      _showReservationDialog(table, selectedDateTime);
                                    },
                                    child: const Center(child: Text('-', style: TextStyle(color: Colors.grey))),
                                  ),
                          )
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // TAB 3: Booked / Reserved Tables
  Widget _buildBookedTablesTab() {
    if (_bookingsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No table reservations found', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookingsList.length,
      itemBuilder: (context, index) {
        final b = _bookingsList[index];
        final bTime = DateTime.parse(b['booking_time']);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.shade100,
              child: const Icon(Icons.bookmark, color: Colors.amber),
            ),
            title: Text(
              'Table ${b['table_number']} • ${b['customer_name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Phone: ${b['customer_phone'] ?? "N/A"} • Guests: ${b['guest_count']} • Time: ${DateFormat('dd MMM yyyy, hh:mm a').format(bTime)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: () {
                    context.go('/dashboard/waiter_order?tableId=${b['table_id']}');
                  },
                  child: const Text('Start Order'),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  // tooltip disabled,
                  onPressed: () async {
                    final db = await DatabaseHelper.instance.database;
                    await db.update('bookings', {'status': 'Cancelled'}, where: 'id = ?', whereArgs: [b['id']]);
                    await _tableRepository.updateTableStatus(b['table_id'], 'Available');
                    _loadTables();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // TAB 4: Active Hold Orders
  Widget _buildHoldOrdersTab() {
    if (_heldOrdersList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pause_circle_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No orders currently on hold', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _heldOrdersList.length,
      itemBuilder: (context, index) {
        final order = _heldOrdersList[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purple.shade50,
              child: const Icon(Icons.pause, color: Colors.purple),
            ),
            title: Text(
              'Order #${order['id']} (Table ${order['table_number'] ?? 'N/A'})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Guest: ${order['customer_name'] ?? 'Guest'} • Total: ₹${order['total_amount']} • Time: ${_getOccupiedDuration(order['order_time'])}',
            ),
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Resume in POS'),
              onPressed: () {
                context.go('/dashboard/pos?tableId=${order['table_id']}&reopenOrderId=${order['id']}');
              },
            ),
          ),
        );
      },
    );
  }
}
