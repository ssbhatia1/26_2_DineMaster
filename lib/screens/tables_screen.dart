import 'dart:async';
import 'package:dine_master/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../repositories/table_repository.dart';
import '../models/table_model.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/searchable_dropdown.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final TableRepository _tableRepository = TableRepository();
  StreamSubscription? _syncSubscription;
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
  TableModel? _selectedGridTable;
  int? _selectedTimeSlotHour;
  String _gridTableSearch = '';
  String _gridSectionFilter = 'All';

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

    _syncSubscription = SyncService.instance.syncEvents.listen((_) {
      if (mounted) _loadTables();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
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
      final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;

      // Load dynamic sections and table types
      final sectionMaps = await db.query(
        'table_sections',
        where: 'restaurant_id = ? OR restaurant_id IS NULL',
        whereArgs: [restaurantId],
      );
      final typeMaps = await db.query(
        'table_types',
        where: 'restaurant_id = ? OR restaurant_id IS NULL',
        whereArgs: [restaurantId],
      );

      List<String> loadedSections = ['All'];
      loadedSections.addAll(sectionMaps.map((m) => m['name'] as String));
      if (loadedSections.length == 1) loadedSections.add('Main Hall'); // Fallback

      List<String> loadedTypes = [];
      loadedTypes.addAll(typeMaps.map((m) => m['name'] as String));
      if (loadedTypes.isEmpty) loadedTypes.add('Standard Table'); // Fallback

      // Load all tables for current restaurant
      final List<Map<String, dynamic>> tableMaps = await db.rawQuery('''
        SELECT t.*, u.name as waiter_name 
        FROM tables t
        LEFT JOIN users u ON t.waiter_id = u.id
        WHERE (t.restaurant_id = ? OR t.restaurant_id IS NULL)
        ORDER BY t.table_number ASC
      ''', [restaurantId]);

      List<Map<String, dynamic>> enrichedTables = [];

      final now = DateTime.now();

      for (var tMap in tableMaps) {
        final tableId = tMap['id'] as int;

        // Find all confirmed bookings for this table
        final List<Map<String, dynamic>> bookingMaps = await db.query(
          'bookings',
          where: 'table_id = ? AND status = ? AND (restaurant_id = ? OR restaurant_id IS NULL)',
          whereArgs: [tableId, 'Confirmed', restaurantId],
          orderBy: 'booking_time ASC',
        );

        // Find active unpaid order (Received, Sent to Kitchen, In Kitchen, Preparing, Ready, Served, Billing Pending, Held)
        final List<Map<String, dynamic>> orderMaps = await db.query(
          'orders',
          where: 'table_id = ? AND status IN (?, ?, ?, ?, ?, ?, ?, ?) AND payment_status != ? AND (restaurant_id = ? OR restaurant_id IS NULL)',
          whereArgs: [
            tableId,
            'Received',
            'Sent to Kitchen',
            'In Kitchen',
            'Preparing',
            'Ready',
            'Served',
            'Billing Pending',
            'Held',
            'Paid',
            restaurantId,
          ],
          orderBy: 'id DESC',
          limit: 1,
        );

        // Classify current active booking (within reservation time window: booking_time to booking_time + 1 hour) vs upcoming
        Map<String, dynamic>? currentBooking;
        final List<Map<String, dynamic>> upcomingBookings = [];

        for (final b in bookingMaps) {
          final bTimeStr = b['booking_time'] as String?;
          if (bTimeStr == null) continue;
          final bTime = DateTime.tryParse(bTimeStr);
          if (bTime == null) continue;

          final slotEnd = bTime.add(const Duration(hours: 1));
          if (!now.isBefore(bTime) && now.isBefore(slotEnd)) {
            currentBooking ??= b;
          } else if (bTime.isAfter(now)) {
            upcomingBookings.add(b);
          }
        }

        Map<String, dynamic>? activeOrder = orderMaps.isNotEmpty ? orderMaps.first : null;

        // Auto-occupy or sanitize table status:
        // - If table has an active order or active booking: status must be 'Occupied'
        // - If bill is paid (no active unpaid order) and no active booking: automatically 'Available'
        var currentStatus = tMap['status'] as String? ?? 'Available';
        if (activeOrder != null || currentBooking != null) {
          if (currentStatus != 'Occupied') {
            await db.update('tables', {'status': 'Occupied'}, where: 'id = ?', whereArgs: [tableId]);
            currentStatus = 'Occupied';
          }
          tMap = Map<String, dynamic>.from(tMap)..['status'] = currentStatus;
        } else {
          // If was Occupied, Reserved, or Billing Pending, but order is paid and no booking -> reset to Available
          if (currentStatus == 'Occupied' || currentStatus == 'Reserved' || currentStatus == 'Billing Pending') {
            await db.update('tables', {'status': 'Available'}, where: 'id = ?', whereArgs: [tableId]);
            currentStatus = 'Available';
          }
          tMap = Map<String, dynamic>.from(tMap)..['status'] = currentStatus;
        }

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
          'active_booking': currentBooking,
          'all_bookings': bookingMaps,
          'upcoming_bookings': upcomingBookings,
          'active_order': activeOrder,
          'order_items_count': orderItemsCount,
        });
      }

      // Also load all booked tables list
      final List<Map<String, dynamic>> allBookings = await db.rawQuery('''
        SELECT b.*, t.table_number 
        FROM bookings b
        JOIN tables t ON b.table_id = t.id
        WHERE b.status = 'Confirmed' AND (b.restaurant_id = ? OR b.restaurant_id IS NULL)
        ORDER BY b.booking_time ASC
      ''', [restaurantId]);

      // Also load all held orders list
      final List<Map<String, dynamic>> allHeldOrders = await db.rawQuery('''
        SELECT o.*, t.table_number 
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.status = 'Held' AND (o.restaurant_id = ? OR o.restaurant_id IS NULL)
        ORDER BY o.order_time DESC
      ''', [restaurantId]);

      if (!mounted) return;
      setState(() {
        _sections = loadedSections;
        _tableTypes = loadedTypes;
        _enrichedTables = enrichedTables;
        _bookingsList = allBookings;
        _heldOrdersList = allHeldOrders;
        if (_selectedGridTable != null) {
          final match = enrichedTables.firstWhere(
            (it) =>
                (it['table'] as TableModel).id == _selectedGridTable!.id ||
                (it['table'] as TableModel).tableNumber == _selectedGridTable!.tableNumber,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            _selectedGridTable = match['table'] as TableModel;
          } else if (enrichedTables.isNotEmpty) {
            _selectedGridTable = enrichedTables.first['table'] as TableModel;
          } else {
            _selectedGridTable = null;
          }
        } else if (enrichedTables.isNotEmpty) {
          _selectedGridTable = enrichedTables.first['table'] as TableModel;
        }
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
      final activeBooking = item['active_booking'] as Map<String, dynamic>?;
      final allBookings = (item['all_bookings'] as List<Map<String, dynamic>>?) ?? [];
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
          if (table.status != 'Occupied' && activeOrder == null && activeBooking == null) return false;
        } else if (_statusFilter == 'Available') {
          if (table.status != 'Available' || activeOrder != null || activeBooking != null) return false;
        } else if (_statusFilter == 'Reserved') {
          if (activeBooking == null && allBookings.isEmpty && table.status != 'Reserved') return false;
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
      final activeBooking = item['active_booking'] as Map<String, dynamic>?;
      final allBookings = (item['all_bookings'] as List<Map<String, dynamic>>?) ?? [];

      if (activeOrder != null) {
        final st = activeOrder['status'];
        if (st == 'Preparing' || st == 'Received') {
          preparing++;
        } else if (st == 'Billing Pending') {
          billing++;
        }
      }

      if (allBookings.isNotEmpty || activeBooking != null || table.status == 'Reserved') {
        reserved++;
      }

      if (table.status == 'Occupied' || activeBooking != null || (activeOrder != null && activeOrder['status'] != 'Held')) {
        occupied++;
      } else if (table.status == 'Available' && activeOrder == null && activeBooking == null) {
        available++;
      } else {
        switch (table.status) {
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
    
    final availableSections = _sections.where((s) => s != 'All').toList();
    if (availableSections.isEmpty) availableSections.add('Main Hall');
    String section = existingTable?.section ?? (availableSections.contains('Main Hall') ? 'Main Hall' : availableSections.first);
    if (!availableSections.contains(section)) availableSections.add(section);

    final availableTypes = List<String>.from(_tableTypes);
    if (availableTypes.isEmpty) availableTypes.add('Standard Table');
    String tableType = existingTable?.tableType ?? (availableTypes.contains('Standard Table') ? 'Standard Table' : availableTypes.first);
    if (!availableTypes.contains(tableType)) availableTypes.add(tableType);

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
                            enabled: !isEditing || (existingTable.status == 'Available'),
                            decoration: InputDecoration(
                              labelText: (!isEditing || (existingTable.status == 'Available')) ? 'Seating Capacity *' : 'Capacity Locked (Active Order)',
                              prefixIcon: const Icon(Icons.chair_alt),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: section,
                            items: availableSections
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
                            items: availableTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
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
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active for Service'),
                            subtitle: const Text('Visible in POS & floor maps'),
                            value: isActive,
                            onChanged: (val) => setDlgState(() => isActive = val),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Reservable'),
                            subtitle: const Text('Can accept advance bookings'),
                            value: isReservable,
                            onChanged: (val) => setDlgState(() => isReservable = val),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              if (isEditing)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmDeleteTable(existingTable.id!, existingTable.tableNumber);
                  },
                )
              else
                const SizedBox.shrink(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
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

                  if (num.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a table number'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  if (cap <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Seating capacity must be at least 1'), backgroundColor: Colors.red),
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
                    restaurantId: DatabaseHelper.currentRestaurantId ?? 1,
                  );

                  try {
                    int tableId;
                    if (isEditing) {
                      await _tableRepository.updateTable(updated);
                      tableId = updated.id!;
                    } else {
                      tableId = await _tableRepository.addTable(updated);
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      await _loadTables();
                      final match = _enrichedTables.firstWhere(
                        (it) =>
                            (it['table'] as TableModel).id == tableId ||
                            (it['table'] as TableModel).tableNumber == num,
                        orElse: () => {},
                      );
                      if (match.isNotEmpty) {
                        setState(() {
                          _selectedGridTable = match['table'] as TableModel;
                        });
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEditing ? 'Table $num updated successfully' : 'Table $num added successfully'),
                          backgroundColor: const Color(0xFF2E7D32),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving table: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
            ],
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${activeOrder['id']} • ${table.displayName}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Guest: $guest • Taken by: $orderTaker • ${_getOccupiedDuration(timeStr)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                  isExpanded: true,
                  hint: const Text('Choose Target Table'),
                  items: availableTables.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(
                        '${t.displayName} (${t.capacity} seats • ${t.section})',
                        overflow: TextOverflow.ellipsis,
                      ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a customer/guest name'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final bookingStart = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                final bookingEnd = bookingStart.add(const Duration(hours: 1));

                final db = await DatabaseHelper.instance.database;

                // Check for overlapping confirmed reservation for this table
                final existingBookings = await db.query(
                  'bookings',
                  where: 'table_id = ? AND status = ?',
                  whereArgs: [table.id, 'Confirmed'],
                );

                bool hasConflict = false;
                for (final eb in existingBookings) {
                  final ebStart = DateTime.tryParse(eb['booking_time'] as String? ?? '');
                  if (ebStart == null) continue;
                  final ebEnd = ebStart.add(const Duration(hours: 1));
                  if (bookingStart.isBefore(ebEnd) && bookingEnd.isAfter(ebStart)) {
                    hasConflict = true;
                    break;
                  }
                }

                if (hasConflict) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Table ${table.tableNumber} already has a confirmed reservation around that time.'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                  return;
                }

                await db.insert('bookings', {
                  'table_id': table.id,
                  'customer_name': nameCtrl.text.trim(),
                  'customer_phone': phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                  'guest_count': int.tryParse(guestsCtrl.text.trim()) ?? table.capacity,
                  'booking_time': bookingStart.toIso8601String(),
                  'status': 'Confirmed',
                  'notes': notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  'restaurant_id': DatabaseHelper.currentRestaurantId ?? 1,
                });

                // Auto-occupy ONLY if current time is within this reservation time window
                final now = DateTime.now();
                if (!now.isBefore(bookingStart) && now.isBefore(bookingEnd)) {
                  await _tableRepository.updateTableStatus(table.id!, 'Occupied');
                }

                if (mounted) {
                  Navigator.pop(context);
                  await _loadTables();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Reservation confirmed for ${table.displayName}'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
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

  // Dialog showing all confirmed reservations for a table
  void _showAllReservationsDialog(TableModel table, List<Map<String, dynamic>> bookings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.bookmark_added, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reservations • ${table.displayName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: bookings.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No active reservations for this table.')),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: bookings.map((b) {
                      final bTime = DateTime.tryParse(b['booking_time'] as String? ?? '');
                      final now = DateTime.now();
                      final isNow = bTime != null &&
                          !now.isBefore(bTime) &&
                          now.isBefore(bTime.add(const Duration(hours: 1)));
                      final timeStr = bTime != null
                          ? DateFormat('EEE, dd MMM yyyy • hh:mm a').format(bTime)
                          : 'N/A';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isNow ? Colors.amber.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isNow ? Colors.amber.shade600 : Colors.grey.shade300,
                            width: isNow ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    b['customer_name'] ?? 'Guest',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isNow ? Colors.amber.shade700 : Colors.blue.shade600,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isNow ? 'ACTIVE NOW' : 'UPCOMING',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '⏰ $timeStr',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                            ),
                            if (b['customer_phone'] != null && (b['customer_phone'] as String).isNotEmpty)
                              Text(
                                '📞 ${b['customer_phone']}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                            Text(
                              '👥 ${b['guest_count'] ?? table.capacity} Guests',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                            if (b['notes'] != null && (b['notes'] as String).isNotEmpty)
                              Text(
                                '📝 Note: ${b['notes']}',
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                  icon: const Icon(Icons.cancel_outlined, size: 14),
                                  label: const Text('Cancel Booking', style: TextStyle(fontSize: 11)),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Cancel Reservation'),
                                        content: Text('Cancel reservation for ${b['customer_name']}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                            onPressed: () => Navigator.pop(c, true),
                                            child: const Text('Yes, Cancel'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final db = await DatabaseHelper.instance.database;
                                      await db.update('bookings', {'status': 'Cancelled'}, where: 'id = ?', whereArgs: [b['id']]);
                                      if (mounted) {
                                        Navigator.pop(ctx);
                                        await _loadTables();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Reservation'),
            onPressed: () {
              Navigator.pop(ctx);
              _showReservationDialog(table);
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;
              final searchField = TextField(
                decoration: InputDecoration(
                  hintText: 'Search by table #, name, section, or notes...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              );

              final dropdowns = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 8),
                    dropdowns,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: searchField,
                  ),
                  const SizedBox(width: 12),
                  dropdowns,
                ],
              );
            },
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
                    mainAxisExtent: 280,
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
    final allBookings = (item['all_bookings'] as List<Map<String, dynamic>>?) ?? [];
    final upcomingBookings = (item['upcoming_bookings'] as List<Map<String, dynamic>>?) ?? [];
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
      displayStatus = 'Occupied';
    } else if (activeBooking != null) {
      displayStatus = 'Occupied';
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
          // Header Bar (Overflow-safe)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: statusColor.withAlpha(25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
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
                        Flexible(
                          child: Text(
                            '(${table.name})',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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
                    const SizedBox(height: 6),
                  ],
                  // Badges: Section & Capacity & Type & All Reservations Count (Overflow-safe)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildChip(table.section, Icons.location_on_outlined),
                        const SizedBox(width: 6),
                        _buildChip('${table.capacity} Seats', Icons.chair_alt),
                        const SizedBox(width: 6),
                        _buildChip(table.tableType, Icons.table_restaurant),
                        if (allBookings.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _showAllReservationsDialog(table, allBookings),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber.shade600, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bookmark, size: 12, color: Colors.amber.shade900),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${allBookings.length} ${allBookings.length == 1 ? 'Booking' : 'Bookings'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Dynamic Context Information
                  if (hasActiveOrder) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${activeOrder['id']} • $orderItemsCount items',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Guest: ${activeOrder['customer_name'] ?? 'Guest'} • ${_getOccupiedDuration(activeOrder['order_time'])}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
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
                            'Reserved Now: ${activeBooking['customer_name']} (${activeBooking['guest_count']} guests)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Slot: ${DateFormat('hh:mm a').format(DateTime.parse(activeBooking['booking_time']))} - ${DateFormat('hh:mm a').format(DateTime.parse(activeBooking['booking_time']).add(const Duration(hours: 1)))}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    if (allBookings.length > 1) ...[
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _showAllReservationsDialog(table, allBookings),
                        child: Text(
                          'View all ${allBookings.length} reservations →',
                          style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ] else if (upcomingBookings.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Next: ${upcomingBookings.first['customer_name']} (${upcomingBookings.first['guest_count']} guests)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'At: ${DateFormat('dd MMM, hh:mm a').format(DateTime.parse(upcomingBookings.first['booking_time']))}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    if (allBookings.length > 1) ...[
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: () => _showAllReservationsDialog(table, allBookings),
                        child: Text(
                          'View all ${allBookings.length} reservations →',
                          style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ] else if (table.status == 'Cleaning') ...[
                    Row(
                      children: [
                        const Icon(Icons.cleaning_services, size: 16, color: Colors.cyan),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Table is currently being sanitized',
                            style: TextStyle(fontSize: 12, color: Colors.cyan, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ] else if (table.status == 'Occupied') ...[
                    Row(
                      children: [
                        const Icon(Icons.people, size: 16, color: Color(0xFF1565C0)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Table manually occupied (Walk-in)',
                            style: TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
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

          // Contextual Action Buttons (Horizontal scroll ensures no RenderFlex overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Configure / Settings
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.grey),
                  onPressed: () => _showTableConfigDialog(table),
                ),

                // Context Actions
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isMergedMember)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(
                              'Order on Table $mergedIntoNumber',
                              style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                            ),
                          )
                        else if (table.status == 'Available' && !hasActiveOrder && !isHeld && activeBooking == null) ...[
                          // Manual Occupation anytime for walk-in guests
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.people_outline, size: 13),
                            label: const Text('Occupy', style: TextStyle(fontSize: 10)),
                            onPressed: () => _updateStatus(table, 'Occupied'),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.bookmark_outline, size: 13),
                            label: const Text('Reserve', style: TextStyle(fontSize: 10)),
                            onPressed: () => _showReservationDialog(table),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.add, size: 13),
                            label: const Text('New Order', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              context.go('/dashboard/waiter_order?tableId=${table.id}');
                            },
                          ),
                        ] else if (hasActiveOrder) ...[
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showOrderDetailsSheet(table, activeOrder),
                            child: const Text('View Order', style: TextStyle(fontSize: 10)),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.point_of_sale, size: 13),
                            label: const Text('Open Order', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                            label: const Text('Resume Order', style: TextStyle(fontSize: 11)),
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
                        ] else if (table.status == 'Occupied' || activeBooking != null) ...[
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _updateStatus(table, 'Available'),
                            child: const Text('Available', style: TextStyle(fontSize: 10)),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showReservationDialog(table),
                            child: const Text('Reserve', style: TextStyle(fontSize: 10)),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => context.go('/dashboard/waiter_order?tableId=${table.id}'),
                            child: const Text('Start Order', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ] else ...[
                          ElevatedButton(
                            onPressed: () => _updateStatus(table, 'Available'),
                            child: const Text('Mark Available', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ],
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

  // TAB 2: Booking Time Grid (Table Selected First + Vertical Slots + Responsive)
  List<TableModel> get _filteredGridTables {
    return _enrichedTables.map((e) => e['table'] as TableModel).where((t) {
      if (_gridSectionFilter != 'All' && t.section != _gridSectionFilter) {
        return false;
      }
      if (_gridTableSearch.isNotEmpty) {
        final query = _gridTableSearch.toLowerCase();
        final matchNumber = t.tableNumber.toLowerCase().contains(query);
        final matchName = t.name?.toLowerCase().contains(query) ?? false;
        if (!matchNumber && !matchName) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildBookingTimeGridTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        if (isDesktop) {
          return _buildDesktopBookingGrid();
        } else {
          return _buildMobileBookingGrid();
        }
      },
    );
  }

  Widget _buildDesktopBookingGrid() {
    final tables = _filteredGridTables;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Table Selection Panel (Table to be selected first)
        SizedBox(
          width: 330,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header & Search
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.table_restaurant, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Select Table First',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${tables.length} tables',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search tables...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (val) => setState(() => _gridTableSearch = val),
                      ),
                      if (_sections.length > 1) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _sections.map((sec) {
                              final isSelected = _gridSectionFilter == sec;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(
                                    sec,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppColors.primary,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (selected) {
                                    if (selected) setState(() => _gridSectionFilter = sec);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Table Cards List
                Expanded(
                  child: tables.isEmpty
                      ? Center(
                          child: Text(
                            'No tables found',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: tables.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final table = tables[index];
                            final isSelected = _selectedGridTable?.id == table.id;
                            return _buildTableSelectionCard(table, isSelected);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        // Right Column: Vertical Booking Time Grid for Selected Table
        Expanded(
          child: Column(
            children: [
              _buildDateNavigatorHeader(),
              const Divider(height: 1),
              Expanded(
                child: _selectedGridTable == null
                    ? _buildNoTableSelectedPlaceholder()
                    : _buildVerticalTimeSlotsGrid(_selectedGridTable!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBookingGrid() {
    final tables = _filteredGridTables;

    return Column(
      children: [
        // 1. Date Navigator
        _buildDateNavigatorHeader(),
        const Divider(height: 1),

        // 2. Horizontal Table Selection Bar (Require table to be selected first)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.grey.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_restaurant, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text(
                    'Select Table First:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  if (_selectedGridTable != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Selected: ${_selectedGridTable!.displayName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: tables.map((t) {
                    final isSelected = _selectedGridTable?.id == t.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedGridTable = t;
                            _selectedTimeSlotHour = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.grey.shade300,
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withAlpha(50),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.table_bar,
                                size: 16,
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${t.capacity}s)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.white70 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Time Slots Content
        Expanded(
          child: _selectedGridTable == null
              ? _buildNoTableSelectedPlaceholder()
              : _buildVerticalTimeSlotsGrid(_selectedGridTable!),
        ),
      ],
    );
  }

  Widget _buildDateNavigatorHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      color: Colors.white,
      child: Row(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                DateFormat('EEE, dd MMMM yyyy').format(_selectedGridDate),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            tooltip: 'Previous Day',
            onPressed: () {
              setState(() => _selectedGridDate = _selectedGridDate.subtract(const Duration(days: 1)));
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 14),
            label: const Text('Select Date'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
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
            tooltip: 'Next Day',
            onPressed: () {
              setState(() => _selectedGridDate = _selectedGridDate.add(const Duration(days: 1)));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableSelectionCard(TableModel table, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedGridTable = table;
          _selectedTimeSlotHour = null;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.table_bar,
                size: 20,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected ? AppColors.primary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${table.section} • ${table.capacity} Seats',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? AppColors.primary.withAlpha(200) : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVE',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoTableSelectedPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.table_restaurant_outlined,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select a Table First',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The booking interface requires a table to be selected before displaying available booking hours.\n'
              'Please select a table to view and manage its time grid.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
            ),
            if (_enrichedTables.isNotEmpty) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.touch_app),
                label: const Text('Select First Table'),
                onPressed: () {
                  setState(() {
                    _selectedGridTable = _enrichedTables.first['table'] as TableModel;
                    _selectedTimeSlotHour = null;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalTimeSlotsGrid(TableModel table) {
    const startHour = 10; // 10 AM
    const endHour = 23; // 11 PM
    final timeSlots = List.generate(endHour - startHour + 1, (index) => startHour + index);

    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedGridDate);
    final bookingsForDay = _bookingsList.where((b) {
      final bTime = b['booking_time'] as String? ?? '';
      return bTime.startsWith(selectedDateStr) && b['table_id'] == table.id;
    }).toList();

    return Column(
      children: [
        // Selected Table Banner with Highlight
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(15),
            border: Border(bottom: BorderSide(color: AppColors.primary.withAlpha(40))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.table_bar, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Table: ${table.displayName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                    ),
                    Text(
                      'Section: ${table.section}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    Text(
                      'Capacity: ${table.capacity} Guests',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${bookingsForDay.length} Booked / ${timeSlots.length} Slots',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Vertical List of Time Slots
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: timeSlots.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final h = timeSlots[index];
              return _buildVerticalTimeSlotCard(table, h, bookingsForDay);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalTimeSlotCard(TableModel table, int h, List<Map<String, dynamic>> bookingsForDay) {
    final hour12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final ampm = h >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:00 $ampm';

    final now = DateTime.now();
    final isCurrentHour = now.hour == h &&
        _selectedGridDate.day == now.day &&
        _selectedGridDate.month == now.month &&
        _selectedGridDate.year == now.year;

    final booking = bookingsForDay.firstWhere((b) {
      final bTime = DateTime.tryParse(b['booking_time'] as String? ?? '');
      return bTime != null && bTime.hour == h;
    }, orElse: () => {});
    final isBooked = booking.isNotEmpty;
    final isSelectedSlot = _selectedTimeSlotHour == h;

    return InkWell(
      onTap: () {
        setState(() => _selectedTimeSlotHour = h);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelectedSlot
              ? AppColors.primary.withAlpha(25)
              : (isBooked ? Colors.amber.shade50.withAlpha(150) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelectedSlot
                ? AppColors.primary
                : (isBooked ? Colors.amber.shade400 : Colors.grey.shade300),
            width: isSelectedSlot ? 2.5 : 1.2,
          ),
          boxShadow: isSelectedSlot
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(5),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Time Indicator Column
            Container(
              width: 105,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelectedSlot
                    ? AppColors.primary
                    : (isCurrentHour ? Colors.blue.shade100 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: isSelectedSlot
                            ? Colors.white
                            : (isCurrentHour ? Colors.blue.shade900 : Colors.grey.shade700),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSelectedSlot
                              ? Colors.white
                              : (isCurrentHour ? Colors.blue.shade900 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1 Hour Slot',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelectedSlot ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Status & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isBooked ? Colors.amber.shade200 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBooked ? Icons.bookmark : Icons.check_circle_outline,
                              size: 12,
                              color: isBooked ? Colors.amber.shade900 : Colors.green.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isBooked ? 'BOOKED' : 'AVAILABLE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isBooked ? Colors.amber.shade900 : Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCurrentHour)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      if (isSelectedSlot)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SELECTED SLOT',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (isBooked) ...[
                    Text(
                      '${booking['customer_name'] ?? 'Booked Customer'} • ${booking['guest_count'] ?? table.capacity} Guests',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (booking['customer_phone'] != null && (booking['customer_phone'] as String).isNotEmpty)
                      Text(
                        'Phone: ${booking['customer_phone']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (booking['notes'] != null && (booking['notes'] as String).isNotEmpty)
                      Text(
                        'Notes: ${booking['notes']}',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ] else ...[
                    Text(
                      'Ready for reservation for ${table.displayName}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Action Buttons
            if (isBooked) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancel Booking'),
                      content: Text('Cancel booking for ${booking['customer_name']} at $timeStr?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Back')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Cancel Booking'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final db = await DatabaseHelper.instance.database;
                    await db.update('bookings', {'status': 'Cancelled'}, where: 'id = ?', whereArgs: [booking['id']]);
                    await _loadTables();
                  }
                },
              ),
            ] else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  visualDensity: VisualDensity.compact,
                  elevation: isSelectedSlot ? 2 : 0,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Book', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() => _selectedTimeSlotHour = h);
                  final selectedDateTime = DateTime(
                    _selectedGridDate.year,
                    _selectedGridDate.month,
                    _selectedGridDate.day,
                    h,
                    0,
                  );
                  _showReservationDialog(table, selectedDateTime);
                },
              ),
            ],
          ],
        ),
      ),
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
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber.shade100,
                  child: const Icon(Icons.bookmark, color: Colors.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Table ${b['table_number']} • ${b['customer_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phone: ${b['customer_phone'] ?? "N/A"} • Guests: ${b['guest_count']} • Time: ${DateFormat('dd MMM yyyy, hh:mm a').format(bTime)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () {
                          context.go('/dashboard/waiter_order?tableId=${b['table_id']}');
                        },
                        child: const Text('Start Order', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        onPressed: () async {
                          final db = await DatabaseHelper.instance.database;
                          await db.update('bookings', {'status': 'Cancelled'}, where: 'id = ?', whereArgs: [b['id']]);
                          await _loadTables();
                        },
                      ),
                    ],
                  ),
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
