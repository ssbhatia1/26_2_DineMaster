import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool _isLoading = true;
  String _username = 'User';

  double _totalSales = 0.0;
  int _liveOrdersCount = 0;
  int _occupiedTablesCount = 0;
  int _totalTablesCount = 0;
  int _lowStockCount = 0;
  List<Map<String, dynamic>> _recentOrders = [];

  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadOverviewData();

    _syncSubscription = SyncService.instance.syncEvents.listen((_) {
      if (mounted) {
        _loadOverviewData();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadOverviewData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'User';

      final db = await DatabaseHelper.instance.database;
      final restaurantId = DatabaseHelper.currentRestaurantId;

      // 1. Total Sales (Paid orders)
      final salesRes = await db.rawQuery(
        "SELECT SUM(total_amount) as total FROM orders WHERE restaurant_id = ? AND payment_status = 'Paid'",
        [restaurantId],
      );
      final totalSalesVal = salesRes.first['total'] as num?;
      final totalSales = totalSalesVal?.toDouble() ?? 0.0;

      // 2. Live Orders (Active states)
      final liveRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM orders WHERE restaurant_id = ? AND status IN ('Received', 'Sent to Kitchen', 'Preparing', 'Ready', 'Cooking', 'Billing Pending')",
        [restaurantId],
      );
      final liveOrders = liveRes.first['count'] as int? ?? 0;

      // 3. Occupied / Total Tables
      final occupiedRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM tables WHERE restaurant_id = ? AND status = 'Occupied'",
        [restaurantId],
      );
      final occupied = occupiedRes.first['count'] as int? ?? 0;

      final totalTablesRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM tables WHERE restaurant_id = ?",
        [restaurantId],
      );
      final totalTables = totalTablesRes.first['count'] as int? ?? 0;

      // 4. Low stock inventory items
      final lowStockRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM inventory WHERE restaurant_id = ? AND current_stock <= low_stock_threshold",
        [restaurantId],
      );
      final lowStock = lowStockRes.first['count'] as int? ?? 0;

      // 5. Recent orders
      final recentOrdersRes = await db.rawQuery('''
        SELECT o.*, t.table_number,
               (SELECT COUNT(*) FROM order_items WHERE order_id = o.id) as item_count
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.restaurant_id = ?
        ORDER BY o.order_time DESC
        LIMIT 5
      ''', [restaurantId]);

      if (mounted) {
        setState(() {
          _username = username;
          _totalSales = totalSales;
          _liveOrdersCount = liveOrders;
          _occupiedTablesCount = occupied;
          _totalTablesCount = totalTables;
          _lowStockCount = lowStock;
          _recentOrders = List<Map<String, dynamic>>.from(recentOrdersRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading overview data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Preparing':
      case 'Cooking':
        return Colors.orange;
      case 'Ready':
        return Colors.blue;
      case 'Served':
      case 'Completed':
      case 'Paid':
        return Colors.green;
      case 'Received':
      case 'Sent to Kitchen':
        return Colors.indigo;
      case 'Held':
        return Colors.amber;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatOrderTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadOverviewData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back, $_username',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Here is what is happening today',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ).animate().fadeIn().slideY(begin: -0.1),
              const SizedBox(height: 32),

              // Metrics Grid
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width >= 1024 ? 4 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMetricCard(
                    'Total Sales',
                    '₹${_totalSales.toStringAsFixed(2)}',
                    Icons.currency_rupee,
                    Colors.green,
                    'Paid revenue today',
                  ),
                  _buildMetricCard(
                    'Live Orders',
                    '$_liveOrdersCount',
                    Icons.restaurant,
                    Colors.orange,
                    'In preparation / active',
                  ),
                  _buildMetricCard(
                    'Occupied Tables',
                    '$_occupiedTablesCount/$_totalTablesCount',
                    Icons.table_bar,
                    Colors.blue,
                    'Active seating layout',
                  ),
                  _buildMetricCard(
                    'Low Stock Items',
                    '$_lowStockCount',
                    Icons.inventory_2,
                    _lowStockCount > 0 ? Colors.red : Colors.grey,
                    _lowStockCount > 0 ? 'Requires attention' : 'Inventory healthy',
                  ),
                ],
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 32),

              // Recent Orders Section
              const Text(
                'Recent Orders',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),

              if (_recentOrders.isEmpty)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'No recent orders',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Orders placed via POS Billing or Waiter Ordering will appear here.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 500.ms)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentOrders.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final order = _recentOrders[index];
                    final orderId = order['id'];
                    final tableNum = order['table_number'] != null ? 'Table ${order['table_number']}' : (order['type'] ?? 'Walk-in');
                    final itemCount = order['item_count'] ?? 0;
                    final timeStr = _formatOrderTime(order['order_time'] as String?);
                    final status = order['status'] as String? ?? 'Received';
                    final statusColor = _statusColor(status);

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: const Icon(Icons.receipt_long, color: AppColors.primary),
                        ),
                        title: Text(
                          'Order #$orderId',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('$tableNum • $itemCount ${itemCount == 1 ? 'Item' : 'Items'} • $timeStr'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withAlpha(50)),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: (500 + (index * 100)).ms).slideX(begin: 0.1);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                Icon(icon, color: color),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
