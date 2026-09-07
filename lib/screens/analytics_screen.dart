import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import 'dart:math';
import '../core/database/database_helper.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Overview statistics
  double _totalSales = 0.0;
  int _totalOrdersCount = 0;
  int _heldOrdersCount = 0;
  double _avgPrepTime = 0.0;

  // Detailed lists
  List<Map<String, dynamic>> _salesByDate = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _chefPerformance = [];
  List<Map<String, dynamic>> _lowStockIngredients = [];
  List<Map<String, dynamic>> _categoryDistribution = [];
  List<Map<String, dynamic>> _paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAnalyticsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Total sales (Paid orders)
      final salesResult = await db.rawQuery("SELECT SUM(total_amount) as total FROM orders WHERE payment_status = 'Paid'");
      final totalSalesVal = salesResult.first['total'] as num?;
      _totalSales = totalSalesVal?.toDouble() ?? 0.0;

      // 2. Total orders count
      final ordersCountResult = await db.rawQuery("SELECT COUNT(*) as count FROM orders");
      _totalOrdersCount = ordersCountResult.first['count'] as int? ?? 0;

      // 3. Held orders count
      final heldResult = await db.rawQuery("SELECT COUNT(*) as count FROM orders WHERE status = 'Held'");
      _heldOrdersCount = heldResult.first['count'] as int? ?? 0;

      // 4. Avg prep time
      final avgPrepResult = await db.rawQuery("SELECT AVG(estimated_time) as avg_time FROM kot");
      final avgTimeVal = avgPrepResult.first['avg_time'] as num?;
      _avgPrepTime = avgTimeVal?.toDouble() ?? 12.5;

      // 5. Sales by date (Last 7 days)
      final dateSalesResult = await db.rawQuery('''
        SELECT SUBSTR(order_time, 1, 10) as date, SUM(total_amount) as total, COUNT(*) as count
        FROM orders
        WHERE payment_status = 'Paid'
        GROUP BY date
        ORDER BY date DESC
        LIMIT 7
      ''');
      _salesByDate = List<Map<String, dynamic>>.from(dateSalesResult);

      // 6. Top selling products
      final topProdResult = await db.rawQuery('''
        SELECT p.name, SUM(oi.quantity) as qty, SUM(oi.quantity * oi.price) as revenue, p.category
        FROM order_items oi
        JOIN products p ON oi.product_id = p.id
        GROUP BY oi.product_id
        ORDER BY qty DESC
        LIMIT 6
      ''');
      _topProducts = List<Map<String, dynamic>>.from(topProdResult);

      // 7. Chef leaderboard
      final chefResult = await db.rawQuery('''
        SELECT chef_name, COUNT(*) as count, AVG(estimated_time) as avg_est
        FROM kot
        WHERE chef_name IS NOT NULL AND chef_name != ''
        GROUP BY chef_name
        ORDER BY count DESC
      ''');
      _chefPerformance = List<Map<String, dynamic>>.from(chefResult);

      // 8. Low stock alerts (< 10 units)
      final stockResult = await db.rawQuery('''
        SELECT name, stock_quantity, unit
        FROM ingredients
        WHERE stock_quantity < 10
        ORDER BY stock_quantity ASC
      ''');
      _lowStockIngredients = List<Map<String, dynamic>>.from(stockResult);

      // 9. Categories sales
      final catResult = await db.rawQuery('''
        SELECT p.category, SUM(oi.quantity * oi.price) as total
        FROM order_items oi
        JOIN products p ON oi.product_id = p.id
        GROUP BY p.category
        ORDER BY total DESC
      ''');
      _categoryDistribution = List<Map<String, dynamic>>.from(catResult);

      // 10. Payment method stats
      final paymentResult = await db.rawQuery('''
        SELECT payment_method, COUNT(*) as count, SUM(total_amount) as total
        FROM orders
        WHERE payment_status = 'Paid' AND payment_method IS NOT NULL
        GROUP BY payment_method
      ''');
      _paymentMethods = List<Map<String, dynamic>>.from(paymentResult);

    } catch (e) {
      print('Error loading database analytics: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            // tooltip disabled,
            onPressed: _loadAnalyticsData,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showExportDialog(context),
            icon: const Icon(Icons.download),
            label: const Text('Export Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Product Sales'),
            Tab(icon: Icon(Icons.kitchen_outlined), text: 'Kitchen Speed'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inventory Warnings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildProductSalesTab(),
          _buildKitchenSpeedTab(),
          _buildInventoryTab(),
        ],
      ),
    );
  }

  // --- TAB 1: OVERVIEW TAB ---
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              double cardWidth = (constraints.maxWidth - 48) / 4;
              if (constraints.maxWidth < 800) {
                cardWidth = (constraints.maxWidth - 16) / 2;
              }
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard(
                    title: 'Total Revenue',
                    value: '₹${_totalSales.toStringAsFixed(2)}',
                    icon: Icons.currency_rupee,
                    color: Colors.green,
                    width: cardWidth,
                  ),
                  _buildStatCard(
                    title: 'Orders Processed',
                    value: _totalOrdersCount.toString(),
                    icon: Icons.shopping_bag_outlined,
                    color: AppColors.primary,
                    width: cardWidth,
                  ),
                  _buildStatCard(
                    title: 'Held Orders',
                    value: _heldOrdersCount.toString(),
                    icon: Icons.pause_circle_outline,
                    color: Colors.orange,
                    width: cardWidth,
                  ),
                  _buildStatCard(
                    title: 'Avg Prep Estimation',
                    value: '${_avgPrepTime.toStringAsFixed(1)} min',
                    icon: Icons.timer_outlined,
                    color: Colors.blue,
                    width: cardWidth,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // Custom Revenue Bar Chart & Payment Breakdown Side-by-Side
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildRevenueChartCard()),
                    const SizedBox(width: 24),
                    Expanded(flex: 1, child: _buildPaymentMethodsCard()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildRevenueChartCard(),
                    const SizedBox(height: 24),
                    _buildPaymentMethodsCard(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            radius: 26,
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChartCard() {
    double maxAmount = 100.0;
    for (var d in _salesByDate) {
      final amt = d['total'] as num? ?? 0.0;
      if (amt > maxAmount) {
        maxAmount = amt.toDouble();
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly Revenue Progression (Last 7 Active Days)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _salesByDate.isEmpty
                ? const SizedBox(
                    height: 200,
                    child: Center(child: Text('No sales records registered yet.', style: TextStyle(color: Colors.grey))),
                  )
                : SizedBox(
                    height: 220,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _salesByDate.reversed.map((d) {
                        final dateStr = d['date'] as String? ?? 'N/A';
                        final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
                        final total = d['total'] as num? ?? 0.0;
                        final count = d['count'] as int? ?? 0;
                        final percentage = total / maxAmount;

                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Container(
                                height: max(10, 150 * percentage),
                                width: 32,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppColors.primaryMaterialColor[300]!, AppColors.primaryMaterialColor[600]!],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                DateFormat('dd MMM').format(parsedDate),
                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '$count bills',
                                style: const TextStyle(fontSize: 9, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsCard() {
    double totalPaidAmt = _paymentMethods.fold(0.0, (sum, item) => sum + (item['total'] as num? ?? 0.0));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Mode Share',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _paymentMethods.isEmpty
                ? const SizedBox(
                    height: 180,
                    child: Center(child: Text('No payment logs.', style: TextStyle(color: Colors.grey))),
                  )
                : Column(
                    children: _paymentMethods.map((mode) {
                      final name = mode['payment_method'] as String? ?? 'Other';
                      final count = mode['count'] as int? ?? 0;
                      final total = mode['total'] as num? ?? 0.0;
                      final percent = totalPaidAmt > 0 ? (total / totalPaidAmt) * 100 : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$name ($count bills)', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('₹${total.toStringAsFixed(2)} (${percent.toStringAsFixed(1)}%)'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent / 100,
                                minHeight: 8,
                                color: name.toLowerCase() == 'cash'
                                    ? Colors.green
                                    : (name.toLowerCase() == 'upi' ? Colors.blue : Colors.orange),
                                backgroundColor: Colors.grey.shade100,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: PRODUCT SALES TAB ---
  Widget _buildProductSalesTab() {
    double totalRevenue = _topProducts.fold(0.0, (sum, item) => sum + (item['revenue'] as num? ?? 0.0));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildTopProductsList(totalRevenue)),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: _buildCategoryDistributionCard()),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildTopProductsList(totalRevenue),
                  const SizedBox(height: 24),
                  _buildCategoryDistributionCard(),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildTopProductsList(double totalRevenue) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Best Selling Products & Items Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _topProducts.isEmpty
                ? const SizedBox(
                    height: 200,
                    child: Center(child: Text('No item sales reported.')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _topProducts.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final p = _topProducts[index];
                      final name = p['name'] as String? ?? '';
                      final qty = p['qty'] as num? ?? 0;
                      final rev = p['revenue'] as num? ?? 0.0;
                      final category = p['category'] as String? ?? 'General';
                      final percent = totalRevenue > 0 ? (rev / totalRevenue) * 100 : 0.0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Text('${index + 1}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Category: $category | Qty Sold: $qty'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₹${rev.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            Text('${percent.toStringAsFixed(1)}% share', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDistributionCard() {
    double totalCatRevenue = _categoryDistribution.fold(0.0, (sum, item) => sum + (item['total'] as num? ?? 0.0));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales distribution by Category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _categoryDistribution.isEmpty
                ? const SizedBox(
                    height: 200,
                    child: Center(child: Text('No categories recorded.')),
                  )
                : Column(
                    children: _categoryDistribution.map((cat) {
                      final name = cat['category'] as String? ?? 'General';
                      final total = cat['total'] as num? ?? 0.0;
                      final percent = totalCatRevenue > 0 ? (total / totalCatRevenue) * 100 : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                              flex: 5,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percent / 100,
                                  minHeight: 12,
                                  color: AppColors.primaryMaterialColor[400]!,
                                  backgroundColor: Colors.grey.shade100,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '₹${total.toStringAsFixed(0)} (${percent.toStringAsFixed(0)}%)',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: KITCHEN SPEED TAB ---
  Widget _buildKitchenSpeedTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kitchen Performance Metrics & Leaderboard',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _chefPerformance.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No chef performance registered. Ensure chef name details are set on KOT actions.')),
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 350,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: _chefPerformance.length,
                  itemBuilder: (context, index) {
                    final chef = _chefPerformance[index];
                    final name = chef['chef_name'] as String;
                    final count = chef['count'] as int;
                    final avgEst = chef['avg_est'] as num? ?? 15.0;

                    return Card(
                      elevation: 0,
                      color: AppColors.primaryLight.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.navyBlue100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary,
                              radius: 24,
                              child: Text(
                                name.substring(0, min(name.length, 2)).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text('KOTs Finished: $count', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text('Avg Speed: ${avgEst.toStringAsFixed(1)} min', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  // --- TAB 4: INVENTORY WARNINGS TAB ---
  Widget _buildInventoryTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Critical Stock Warnings (< 10 Units Remaining)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (_lowStockIngredients.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_lowStockIngredients.length} ingredients running low',
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _lowStockIngredients.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                        SizedBox(height: 16),
                        Text('All stocks are within optimal levels!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('No items are currently below safety threshold.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _lowStockIngredients.length,
                    itemBuilder: (context, index) {
                      final item = _lowStockIngredients[index];
                      final name = item['name'] as String;
                      final stock = item['stock_quantity'] as num? ?? 0.0;
                      final unit = item['unit'] as String? ?? 'kg';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.red.shade100),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade50,
                            child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Threshold Status: Depleted'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$stock $unit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                              const Text('Low Stock Alert', style: TextStyle(color: Colors.grey, fontSize: 11)),
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

  // --- EXPORT OPTION DIALOG ---
  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 8),
            Text('Export Business Statement'),
          ],
        ),
        content: const Text(
          'Choose the accounting statement you would like to generate and export. '
          'This will compile total revenue, tax receipts, category percentages, and inventory logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('GST Tax Audit'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Sales Statement (PDF)'),
          ),
        ],
      ),
    );
  }
}
