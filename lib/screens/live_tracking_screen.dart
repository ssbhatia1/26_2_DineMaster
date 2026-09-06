import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/sync_service.dart';

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  late TabController _tabController;
  bool _isLoading = true;
  Timer? _pollingTimer;
  StreamSubscription? _syncSubscription;

  // Real-time data lists
  List<Map<String, dynamic>> _liveOrders = [];
  List<Map<String, dynamic>> _auditLogs = [];
  
  // Analytics State
  double _avgPrepTime = 12.5; // fallback defaults
  int _totalCompleted = 0;
  int _totalDelayed = 0;
  List<Map<String, dynamic>> _chefStats = [];
  List<Map<String, dynamic>> _peakHours = [];

  // Selected Order for Customer QR view simulation
  Map<String, dynamic>? _selectedCustomerOrder;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllTrackingData();
    
    // Live WebSocket synchronization
    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted) {
        _loadAllTrackingData(silent: true);
      }
    });

    // Safety fallback poll every 10 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadAllTrackingData(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _syncSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllTrackingData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final db = await _dbHelper.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;

      // 1. Fetch live orders (not completed or fully served in past days)
      final List<Map<String, dynamic>> orderMaps = await db.query(
        'orders',
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
        orderBy: 'order_time DESC',
      );

      List<Map<String, dynamic>> liveOrders = [];
      for (var o in orderMaps) {
        final orderId = o['id'] as int;

        // Fetch active KOTs status & chef
        final List<Map<String, dynamic>> kots = await db.query(
          'kot',
          columns: ['id', 'status', 'estimated_time', 'chef_name', 'created_at', 'delay_reason'],
          where: 'order_id = ?',
          whereArgs: [orderId],
        );

        String chefName = 'Unassigned';
        int estTime = 15;
        String? delayReason;
        if (kots.isNotEmpty) {
          chefName = kots.first['chef_name'] as String? ?? 'Unassigned';
          estTime = kots.first['estimated_time'] as int? ?? 15;
          delayReason = kots.first['delay_reason'] as String?;
        }

        // Get table details if Dine-in
        String tableNumber = 'Takeaway';
        final tableId = o['table_id'] as int?;
        if (tableId != null) {
          final List<Map<String, dynamic>> tables = await db.query(
            'tables',
            columns: ['table_number'],
            where: 'id = ?',
            whereArgs: [tableId],
          );
          if (tables.isNotEmpty) {
            tableNumber = tables.first['table_number'] as String;
          }
        }

        liveOrders.add({
          'id': orderId,
          'customer_name': o['customer_name'] ?? 'Walk-in Guest',
          'customer_phone': o['customer_phone'] ?? 'N/A',
          'total_amount': o['total_amount'],
          'status': o['status'] ?? 'Received',
          'type': o['type'] ?? 'Takeaway',
          'order_time': o['order_time'],
          'chef_name': chefName,
          'estimated_time': estTime,
          'delay_reason': delayReason,
          'table_number': tableNumber,
          'kots_count': kots.length,
        });
      }

      // 2. Fetch Audit Logs
      final List<Map<String, dynamic>> logs = await db.query(
        'order_status_logs',
        orderBy: 'changed_at DESC',
        limit: 30,
      );

      // 3. Performance & Analytics Calculations
      // Avg prep time (ready_at - started_cooking_at)
      final List<Map<String, dynamic>> completedKots = await db.rawQuery('''
        SELECT started_cooking_at, ready_at, chef_name 
        FROM kot 
        WHERE ready_at IS NOT NULL AND started_cooking_at IS NOT NULL
      ''');

      double totalPrepMinutes = 0;
      int completedCount = 0;
      Map<String, List<double>> chefTimes = {};
      
      for (var k in completedKots) {
        final start = DateTime.tryParse(k['started_cooking_at'] as String);
        final ready = DateTime.tryParse(k['ready_at'] as String);
        if (start != null && ready != null) {
          final diff = ready.difference(start).inSeconds / 60.0;
          totalPrepMinutes += diff;
          completedCount++;

          final chef = k['chef_name'] as String? ?? 'Kitchen';
          chefTimes.putIfAbsent(chef, () => []).add(diff);
        }
      }

      // Chef Stats
      List<Map<String, dynamic>> chefStats = [];
      chefTimes.forEach((chef, times) {
        final avg = times.reduce((a, b) => a + b) / times.length;
        chefStats.add({
          'chef_name': chef,
          'orders_completed': times.length,
          'avg_time': avg.toStringAsFixed(1),
        });
      });

      // Peak Hours
      final List<Map<String, dynamic>> rawHours = await db.rawQuery('''
        SELECT strftime('%H', order_time) as hour, COUNT(*) as count 
        FROM orders 
        GROUP BY hour 
        ORDER BY count DESC
      ''');
      List<Map<String, dynamic>> peakHours = rawHours.map((rh) {
        final h = int.tryParse(rh['hour'] as String? ?? '0') ?? 0;
        final ampm = h >= 12 ? 'PM' : 'AM';
        final displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        return {
          'time_range': '$displayHour:00 $ampm',
          'order_count': rh['count'],
        };
      }).toList();

      final int completedOrdersCount = orderMaps.where((o) => o['status'] == 'Completed').length;
      final int delayedOrdersCount = liveOrders.where((o) => o['delay_reason'] != null).length;

      if (mounted) {
        setState(() {
          _liveOrders = liveOrders;
          _auditLogs = logs;
          _avgPrepTime = completedCount > 0 ? (totalPrepMinutes / completedCount) : 12.5;
          _totalCompleted = completedOrdersCount;
          _totalDelayed = delayedOrdersCount;
          _chefStats = chefStats;
          _peakHours = peakHours;
          
          if (_selectedCustomerOrder != null) {
            // Update reference state of currently tracked order
            final matched = _liveOrders.firstWhere(
              (o) => o['id'] == _selectedCustomerOrder!['id'],
              orElse: () => _selectedCustomerOrder!,
            );
            _selectedCustomerOrder = matched;
          } else if (_liveOrders.isNotEmpty) {
            _selectedCustomerOrder = _liveOrders.first;
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading tracking analytics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateOrderStatusDirectly(int orderId, String newStatus) async {
    try {
      final db = await _dbHelper.database;
      final nowStr = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        // Update Order Status
        await txn.update(
          'orders',
          {'status': newStatus},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        // Update KOT statuses if changing core tracking stages
        String? kotStatus;
        if (newStatus == 'Preparing') {
          kotStatus = 'Cooking';
        } else if (newStatus == 'Ready') {
          kotStatus = 'Ready';
        } else if (newStatus == 'Completed' || newStatus == 'Served') {
          kotStatus = 'Served';
        }

        if (kotStatus != null) {
          await txn.update(
            'kot',
            {'status': kotStatus},
            where: 'order_id = ?',
            whereArgs: [orderId],
          );
          await txn.update(
            'order_items',
            {'status': kotStatus},
            where: 'order_id = ?',
            whereArgs: [orderId],
          );
        }

        // Insert timeline audit log
        await txn.insert('order_status_logs', {
          'order_id': orderId,
          'status': newStatus,
          'changed_at': nowStr,
          'changed_by': 'Admin Dashboard',
          'notes': 'Order status changed manually to $newStatus.',
        });
      });

      _loadAllTrackingData(silent: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #$orderId marked as $newStatus')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating order: $e')),
      );
    }
  }

  // Get index for tracking progress bar
  double _getProgressValue(String status) {
    switch (status) {
      case 'Received':
        return 0.15;
      case 'Sent to Kitchen':
        return 0.35;
      case 'Preparing':
        return 0.55;
      case 'Ready':
        return 0.75;
      case 'Served':
        return 0.90;
      case 'Completed':
        return 1.0;
      case 'Cancelled':
        return 0.0;
      default:
        return 0.1;
    }
  }

  String _getStatusDescription(String status) {
    switch (status) {
      case 'Received':
        return 'We have received your order at the counter.';
      case 'Sent to Kitchen':
        return 'Kitchen staff has accepted your ticket.';
      case 'Preparing':
        return 'Chef is actively preparing your delicious food!';
      case 'Ready':
        return 'Your hot meal is ready to be collected/served!';
      case 'Served':
        return 'Food has been served at your table.';
      case 'Completed':
        return 'Billing is paid and order is completed. Thank you!';
      case 'Cancelled':
        return 'This order has been cancelled.';
      default:
        return 'Processing your order...';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Received':
        return Colors.blue;
      case 'Sent to Kitchen':
        return Colors.orange;
      case 'Preparing':
        return Colors.amber;
      case 'Ready':
        return Colors.purple;
      case 'Served':
        return Colors.teal;
      case 'Completed':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Order Tracker & Performance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_customize), text: 'Live Status Tracker'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Customer QR View'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Performance Analytics'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLiveStatusTrackerView(),
                _buildCustomerQRView(),
                _buildPerformanceAnalyticsView(),
              ],
            ),
    );
  }

  // VIEW 1: Live Status Grid Tracker (Kanban-like rows)
  Widget _buildLiveStatusTrackerView() {
    final activeStages = ['Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served'];
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Restaurant Order Flow',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_liveOrders.where((o) => o['status'] != 'Completed' && o['status'] != 'Cancelled').length} Active Orders',
                style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _liveOrders.length,
              itemBuilder: (context, index) {
                final order = _liveOrders[index];
                final status = order['status'] as String;
                final isDone = status == 'Completed' || status == 'Cancelled';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.deepPurple.shade50,
                              child: Text('#${order['id']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        order['customer_name'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: order['type'] == 'Dine-in' ? Colors.blue.shade50 : Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          order['type'] == 'Dine-in' ? 'Table ${order['table_number']}' : 'Takeaway',
                                          style: TextStyle(
                                            color: order['type'] == 'Dine-in' ? Colors.blue.shade900 : Colors.orange.shade900,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Time: ${DateFormat('hh:mm a').format(DateTime.tryParse(order['order_time']) ?? DateTime.now())} | Total: ₹${order['total_amount']}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Status Dropdown selector to manual adjust (Simulator)
                            DropdownButton<String>(
                              value: activeStages.contains(status) ? status : (isDone ? status : 'Received'),
                              underline: const SizedBox(),
                              style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 13),
                              items: ['Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Served', 'Completed', 'Cancelled']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  _updateOrderStatusDirectly(order['id'] as int, val);
                                }
                              },
                            ),
                          ],
                        ),
                        
                        const Divider(height: 16),
                        
                        // Progress visualizer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kitchen Cook Progress', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                            Text('Est Prep: ${order['estimated_time']} mins', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _getProgressValue(status),
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(status)),
                            minHeight: 8,
                          ),
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

  // VIEW 2: Customer Live Order Tracking View (QR Simulator)
  Widget _buildCustomerQRView() {
    if (_selectedCustomerOrder == null) {
      return const Center(child: Text('Create an order to track customer QR status'));
    }

    final order = _selectedCustomerOrder!;
    final status = order['status'] as String;
    final progress = _getProgressValue(status);
    final orderTime = DateTime.tryParse(order['order_time']) ?? DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withAlpha(20),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: const Text('Customer Live Order Tracking', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                centerTitle: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                leading: const Icon(Icons.qr_code, color: Colors.deepPurple),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Active tracking header card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade900],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('ORDER #${order['id']}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(order['type'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Estimating Serving Time',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            Text(
                              '${order['estimated_time']} Minutes',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.access_time, color: Colors.white70, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Ordered at: ${DateFormat('hh:mm a').format(orderTime)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Progress bar and active status text
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getStatusColor(status)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusDescription(status),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      // Steps Visualizer Vertical Progress
                      _buildProgressStep(
                        title: 'Order Placed & Confirmed',
                        subtitle: 'Received at counter',
                        isCompleted: progress >= 0.15,
                        isActive: status == 'Received',
                        icon: Icons.check_circle_outline,
                      ),
                      _buildProgressStep(
                        title: 'Sent to Kitchen Queue',
                        subtitle: 'Ticket verified by staff',
                        isCompleted: progress >= 0.35,
                        isActive: status == 'Sent to Kitchen',
                        icon: Icons.send,
                      ),
                      _buildProgressStep(
                        title: 'Preparing Food',
                        subtitle: 'Chef has started cooking',
                        isCompleted: progress >= 0.55,
                        isActive: status == 'Preparing',
                        icon: Icons.outdoor_grill,
                      ),
                      _buildProgressStep(
                        title: 'Ready for Collection',
                        subtitle: 'Dish is fully prepared',
                        isCompleted: progress >= 0.75,
                        isActive: status == 'Ready',
                        icon: Icons.room_service_outlined,
                      ),
                      _buildProgressStep(
                        title: 'Served / Picked Up',
                        subtitle: 'Enjoy your meal!',
                        isCompleted: progress >= 1.0,
                        isActive: status == 'Completed' || status == 'Served',
                        icon: Icons.celebration,
                      ),

                      const SizedBox(height: 20),
                      
                      // Dropdown to switch active simulated customer tracking
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonFormField<int>(
                          value: order['id'],
                          decoration: const InputDecoration(labelText: 'Track different active order', border: InputBorder.none),
                          items: _liveOrders.map((o) => DropdownMenuItem(
                            value: o['id'] as int,
                            child: Text('Order #${o['id']} - ${o['customer_name']}'),
                          )).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedCustomerOrder = _liveOrders.firstWhere((o) => o['id'] == val);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
    required IconData icon,
  }) {
    final activeColor = isActive ? Colors.deepPurple : (isCompleted ? Colors.green : Colors.grey.shade300);
    final labelColor = isActive ? Colors.black : (isCompleted ? Colors.grey.shade800 : Colors.grey.shade400);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: activeColor.withAlpha(20),
                  border: Border.all(color: activeColor, width: 2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: activeColor),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isCompleted ? Colors.green : Colors.grey.shade200,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: labelColor),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // VIEW 3: Performance Reports & Audit Logs Viewer
  Widget _buildPerformanceAnalyticsView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kitchen Performance KPI & Audit Trail',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Statistics metric row
            LayoutBuilder(builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isMobile ? 2 : 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _buildMetricStat('Avg Prep Speed', '${_avgPrepTime.toStringAsFixed(1)} min', Icons.timer, Colors.blue),
                  _buildMetricStat('Completed Bills', '$_totalCompleted Orders', Icons.assignment_turned_in, Colors.green),
                  _buildMetricStat('Delayed Orders', '$_totalDelayed Bills', Icons.error_outline, Colors.red),
                  _buildMetricStat('Peak Workload Hour', _peakHours.isNotEmpty ? _peakHours.first['time_range'] : 'N/A', Icons.wb_sunny_outlined, Colors.amber),
                ],
              );
            }),

            const SizedBox(height: 24),
            
            // Peak Hours Table
            const Text('Peak Order Volume Hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Table(
                border: TableBorder.symmetric(inside: BorderSide(color: Colors.grey.shade100)),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Colors.grey),
                    children: [
                      Padding(padding: EdgeInsets.all(10.0), child: Text('Time Frame', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(10.0), child: Text('Total Orders Logged', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  if (_peakHours.isEmpty)
                    const TableRow(children: [
                      Padding(padding: EdgeInsets.all(12.0), child: Text('No order history recorded yet.')),
                      Padding(padding: EdgeInsets.all(12.0), child: Text('')),
                    ])
                  else
                    ..._peakHours.map((ph) => TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(10.0), child: Text(ph['time_range'])),
                        Padding(padding: const EdgeInsets.all(10.0), child: Text('${ph['order_count']} orders', style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    )),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Chef Performance Speeds
            const Text('Chef Preparation Speeds', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Table(
                border: TableBorder.symmetric(inside: BorderSide(color: Colors.grey.shade100)),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Colors.grey),
                    children: [
                      Padding(padding: EdgeInsets.all(10.0), child: Text('Chef / Kitchen Unit', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(10.0), child: Text('Completed Tickets', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(10.0), child: Text('Avg Prep Speed', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  if (_chefStats.isEmpty)
                    const TableRow(children: [
                      Padding(padding: EdgeInsets.all(12.0), child: Text('No completed tickets for chef performance analytics.')),
                      Padding(padding: EdgeInsets.all(12.0), child: Text('')),
                      Padding(padding: EdgeInsets.all(12.0), child: Text('')),
                    ])
                  else
                    ..._chefStats.map((cs) => TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(10.0), child: Text(cs['chef_name'])),
                        Padding(padding: const EdgeInsets.all(10.0), child: Text('${cs['orders_completed']}')),
                        Padding(padding: const EdgeInsets.all(10.0), child: Text('${cs['avg_time']} mins', style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold))),
                      ],
                    )),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Timeline Audit Log List
            const Text('Live Timeline logs Audit Trail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _auditLogs.length,
                separatorBuilder: (context, index) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final log = _auditLogs[index];
                  final parsedTime = DateTime.tryParse(log['changed_at'] as String) ?? DateTime.now();

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.blueGrey.shade300, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Order #${log['order_id']} → Status: ${log['status']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  DateFormat('hh:mm a').format(parsedTime),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${log['notes'] ?? ''} [By: ${log['changed_by'] ?? 'System'}]',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricStat(String label, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const Spacer(),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
