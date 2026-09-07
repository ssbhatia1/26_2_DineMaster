import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dine_master/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/database/database_helper.dart';
import 'pdf_preview_screen.dart';

class OrdersHistoryScreen extends StatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  String _selectedOrderType = 'All';
  String _selectedPaymentStatus = 'All';
  String _selectedOrderStatus = 'All';

  @override
  void initState() {
    super.initState();
    // Default to last 30 days
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final restId = DatabaseHelper.currentRestaurantId;

      String query = '''
        SELECT o.*, t.table_number 
        FROM orders o
        LEFT JOIN tables t ON o.table_id = t.id
        WHERE o.restaurant_id = ?
      ''';
      List<dynamic> args = [restId];

      // Search Filter
      final searchVal = _searchController.text.trim();
      if (searchVal.isNotEmpty) {
        query += ''' AND (
          o.id LIKE ? OR 
          o.customer_name LIKE ? OR 
          o.customer_phone LIKE ? OR 
          t.table_number LIKE ?
        )''';
        args.addAll(['%$searchVal%', '%$searchVal%', '%$searchVal%', '%$searchVal%']);
      }

      // Order Type Filter
      if (_selectedOrderType != 'All') {
        query += ' AND o.type = ?';
        args.add(_selectedOrderType);
      }

      // Payment Status Filter
      if (_selectedPaymentStatus != 'All') {
        query += ' AND o.payment_status = ?';
        args.add(_selectedPaymentStatus);
      }

      // Order Status Filter
      if (_selectedOrderStatus != 'All') {
        query += ' AND o.status = ?';
        args.add(_selectedOrderStatus);
      }

      // Date Range Filter
      if (_selectedDateRange != null) {
        String startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start) + "T00:00:00";
        String endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end) + "T23:59:59";
        query += ' AND o.order_time BETWEEN ? AND ?';
        args.addAll([startStr, endStr]);
      }

      query += ' ORDER BY o.order_time DESC';

      final orders = await db.rawQuery(query, args);

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading orders: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getOrderItems(int orderId) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery('''
      SELECT oi.*, p.name as product_name 
      FROM order_items oi
      JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = ?
    ''', [orderId]);
  }

  void _showInvoice(Map<String, dynamic> order) async {
    final items = await _getOrderItems(order['id']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Invoice #${order['id']}'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: order['status'] == 'Served' || order['status'] == 'Completed' || order['status'] == 'Received'
                    ? Colors.green
                    : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                order['status'],
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.parse(order['order_time']))}'),
              Text('Type: ${order['type']}'),
              if (order['table_number'] != null) Text('Table: ${order['table_number']}'),
              if (order['customer_name'] != null) Text('Customer: ${order['customer_name']}'),
              if (order['customer_phone'] != null) Text('Phone: ${order['customer_phone']}'),
              if (order['order_taker_name'] != null) ...[
                const SizedBox(height: 4),
                Text('Order Taken By: ${order['order_taker_name']} (ID: ${order['order_taker_id'] ?? "N/A"})'),
              ],
              if (order['delivered_by_name'] != null) ...[
                const SizedBox(height: 4),
                Text('Delivered By: ${order['delivered_by_name']} (ID: ${order['delivered_by_id'] ?? "N/A"})'),
              ],
              if (order['delivery_timestamp'] != null) ...[
                const SizedBox(height: 4),
                Text('Delivered At: ${DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.parse(order['delivery_timestamp']))}'),
              ],
              const Divider(height: 24),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                  Text('Qty', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 16),
                  Text('Price', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 16),
                  Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(item['product_name'])),
                    Text('${item['quantity']}'),
                    const SizedBox(width: 16),
                    Text('₹${item['price']}'),
                    const SizedBox(width: 16),
                    Text('₹${((item['price'] as num) * (item['quantity'] as num)).toStringAsFixed(2)}'),
                  ],
                ),
              )).toList(),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('₹${order['total_amount']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showOrderHistoryAndKotDialog(order['id']);
            },
            icon: const Icon(Icons.track_changes),
            label: const Text('Track KOT'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () => _printInvoice(order, items),
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          ElevatedButton.icon(
            onPressed: () => _previewInvoice(order, items),
            icon: const Icon(Icons.preview),
            label: const Text('Preview Invoice'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.go('/dashboard/pos?orderId=${order['id']}');
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Reopen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () => _confirmDelete(order['id']),
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
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

  Future<void> _printInvoice(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final pdf = await _generatePdfDocument(order, items);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  void _previewInvoice(Map<String, dynamic> order, List<Map<String, dynamic>> items) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          title: 'Invoice #${order['id']}',
          buildPdf: (format) async {
            final pdf = await _generatePdfDocument(order, items);
            return pdf.save();
          },
        ),
      ),
    );
  }

  Future<pw.Document> _generatePdfDocument(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Invoice #${order['id']}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Date: ${order['order_time']}'),
              pw.Text('Type: ${order['type']}'),
              if (order['table_number'] != null) pw.Text('Table: ${order['table_number']}'),
              if (order['customer_name'] != null) pw.Text('Customer: ${order['customer_name']}'),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Item', 'Qty', 'Price', 'Total'],
                data: items.map((item) => [
                  item['product_name'],
                  item['quantity'].toString(),
                  'Rs. ${item['price']}',
                  'Rs. ${(item['price'] * item['quantity']).toStringAsFixed(2)}'
                ]).toList(),
              ),
              pw.SizedBox(height: 20),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Total: Rs. ${order['total_amount']}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  Future<void> _processPayment(int orderId, String method) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('orders', {
      'payment_status': 'Paid',
      'payment_method': method,
      'status': 'Paid',
    }, where: 'id = ?', whereArgs: [orderId]);
    
    // Log payment to payments table
    final orderMaps = await db.query('orders', columns: ['total_amount'], where: 'id = ?', whereArgs: [orderId]);
    if (orderMaps.isNotEmpty) {
      await db.insert('payments', {
        'order_id': orderId,
        'amount': orderMaps.first['total_amount'],
        'payment_mode': method,
        'payment_time': DateTime.now().toIso8601String(),
      });
    }


    _loadOrders(); // Refresh list
  }

  void _showPaymentSelectionDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay Bill Amount - Order #${order['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Amount to Pay: ₹${order['total_amount']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.money),
              label: const Text('Pay via Cash'),
              onPressed: () {
                Navigator.pop(context);
                _processPayment(order['id'], 'Cash');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code),
              label: const Text('Pay via UPI'),
              onPressed: () {
                Navigator.pop(context);
                _processPayment(order['id'], 'UPI');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.credit_card),
              label: const Text('Pay via Card'),
              onPressed: () {
                Navigator.pop(context);
                _processPayment(order['id'], 'Card');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text('Pay via Wallet'),
              onPressed: () {
                Navigator.pop(context);
                _processPayment(order['id'], 'Wallet');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.call_split),
              label: const Text('Split Payment'),
              onPressed: () {
                Navigator.pop(context);
                _showSplitPaymentDialog(order);
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  void _showSplitPaymentDialog(Map<String, dynamic> order) {
    final cashController = TextEditingController();
    final upiController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Split Payment for #${order['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total Amount: ₹${order['total_amount']}'),
            const SizedBox(height: 8),
            TextField(
              controller: cashController,
              decoration: const InputDecoration(labelText: 'Cash Amount'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: upiController,
              decoration: const InputDecoration(labelText: 'UPI Amount'),
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
              final cash = double.tryParse(cashController.text) ?? 0;
              final upi = double.tryParse(upiController.text) ?? 0;
              if (cash + upi == order['total_amount']) {
                final db = await DatabaseHelper.instance.database;
                await db.update('orders', {
                  'payment_status': 'Paid',
                  'payment_method': 'Split (Cash: $cash, UPI: $upi)',
                  'status': 'Paid',
                }, where: 'id = ?', whereArgs: [order['id']]);

                // Log payment to payments table
                await db.insert('payments', {
                  'order_id': order['id'],
                  'amount': order['total_amount'],
                  'payment_mode': 'Split (Cash: $cash, UPI: $upi)',
                  'payment_time': DateTime.now().toIso8601String(),
                });

                Navigator.pop(context);
                _loadOrders();
              } else {

              }
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete order #$orderId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close confirm dialog
              Navigator.pop(context); // Close invoice dialog
              await _deleteOrder(orderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrder(int orderId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await db.delete('orders', where: 'id = ?', whereArgs: [orderId]);
      await db.delete('payments', where: 'order_id = ?', whereArgs: [orderId]);
      

      _loadOrders(); // Refresh list
    } catch (e) {

    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Dynamic Filters Dashboard Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    final searchBar = TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by Order #, Customer, Phone, or Table...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (_) => _loadOrders(),
                    );

                    final dateButton = ElevatedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _selectedDateRange == null
                            ? 'Filter Date'
                            : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          initialDateRange: _selectedDateRange,
                        );
                        if (picked != null) {
                          setState(() => _selectedDateRange = picked);
                          _loadOrders();
                        }
                      },
                    );

                    final dropdownType = DropdownButtonFormField<String>(
                      value: _selectedOrderType,
                      decoration: const InputDecoration(labelText: 'Order Type', border: InputBorder.none),
                      items: ['All', 'Dine-in', 'Takeaway', 'Parcel', 'Delivery']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedOrderType = val);
                          _loadOrders();
                        }
                      },
                    );

                    final dropdownStatus = DropdownButtonFormField<String>(
                      value: _selectedOrderStatus,
                      decoration: const InputDecoration(labelText: 'Order Status', border: InputBorder.none),
                      items: ['All', 'Received', 'Preparing', 'Ready', 'Served', 'Completed', 'Held']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedOrderStatus = val);
                          _loadOrders();
                        }
                      },
                    );

                    final dropdownPayment = DropdownButtonFormField<String>(
                      value: _selectedPaymentStatus,
                      decoration: const InputDecoration(labelText: 'Payment Status', border: InputBorder.none),
                      items: ['All', 'Paid', 'Unpaid']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedPaymentStatus = val);
                          _loadOrders();
                        }
                      },
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchBar,
                          const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: dateButton),
                          const SizedBox(height: 12),
                          dropdownType,
                          const SizedBox(height: 8),
                          dropdownStatus,
                          const SizedBox(height: 8),
                          dropdownPayment,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(flex: 2, child: searchBar),
                            const SizedBox(width: 16),
                            dateButton,
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: dropdownType),
                            const SizedBox(width: 16),
                            Expanded(child: dropdownStatus),
                            const SizedBox(width: 16),
                            Expanded(child: dropdownPayment),
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ),
          ),
          
          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? const Center(child: Text('No orders found matching filters.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) {
                          final order = _orders[index];
                          final date = DateTime.parse(order['order_time']);
                          final isCompleted = order['status'] == 'Served' || order['status'] == 'Completed' || order['status'] == 'Received';
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primary.withAlpha(25),
                                    child: const Icon(Icons.receipt, color: AppColors.primary),
                                  ),
                                  title: Text(
                                    'Order #${order['id']} - ₹${order['total_amount']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    '${DateFormat('yyyy-MM-dd hh:mm a').format(date)} | Type: ${order['type']}'
                                    '${order['table_number'] != null ? " | Table: ${order['table_number']}" : ""}'
                                    '${order['customer_name'] != null ? " | Name: ${order['customer_name']}" : ""}',
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isCompleted ? Colors.green.withAlpha(25) : Colors.orange.withAlpha(25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      order['status'],
                                      style: TextStyle(
                                        color: isCompleted ? Colors.green : Colors.orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  onTap: () => _showInvoice(order),
                                ),
                                if (order['status'] == 'Held' || order['status'] == 'Ready')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.edit_note),
                                          label: const Text('Reopen & Edit'),
                                          onPressed: () {
                                            context.go('/dashboard/pos?orderId=${order['id']}&tableId=${order['table_id'] ?? ""}');
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.payment),
                                          label: const Text('Proceed to Checkout'),
                                          onPressed: () {
                                            context.go('/dashboard/pos?orderId=${order['id']}&tableId=${order['table_id'] ?? ""}');
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order['status'] == 'Served' || order['status'] == 'Completed' || order['status'] == 'Received' || order['status'] == 'Paid')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Payment Status: ${order['payment_status'] ?? 'Unpaid'}' +
                                              (order['payment_method'] != null ? ' (${order['payment_method']})' : ''),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: order['payment_status'] == 'Paid' ? Colors.green : Colors.red,
                                              ),
                                            ),
                                            Wrap(
                                              spacing: 8,
                                              children: [
                                                if (order['payment_status'] != 'Paid')
                                                  ElevatedButton.icon(
                                                    icon: const Icon(Icons.payment),
                                                    label: const Text('Pay Bill Amount'),
                                                    onPressed: () => _showPaymentSelectionDialog(order),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppColors.primary,
                                                      foregroundColor: Colors.white,
                                                    ),
                                                  )
                                                else
                                                  TextButton.icon(
                                                    icon: const Icon(Icons.print_outlined),
                                                    label: const Text('Reprint Invoice'),
                                                    onPressed: () => _showInvoice(order),
                                                  ),
                                              ],
                                            ),
                                          ],
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
    );
  }
}
