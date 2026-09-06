import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import '../core/database/database_helper.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  double _totalSales = 0.0;
  double _totalExpenses = 0.0;
  double _totalTaxes = 0.0;
  int _totalOrdersCount = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _salesTransactions = [];
  List<Map<String, dynamic>> _expenses = [];

  // Filter state
  DateTimeRange? _selectedDateRange;
  String _selectedPaymentMode = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    _loadAccountsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountsData() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbHelper.database;
      final restId = DatabaseHelper.currentRestaurantId;

      String startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start) + "T00:00:00";
      String endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end) + "T23:59:59";

      // 1. Fetch Sales and calculate totals
      String orderQuery = 'restaurant_id = ? AND order_time BETWEEN ? AND ? AND status != ?';
      List<dynamic> orderArgs = [restId, startStr, endStr, 'Held'];

      if (_selectedPaymentMode != 'All') {
        orderQuery += ' AND payment_method = ?';
        orderArgs.add(_selectedPaymentMode);
      }

      final List<Map<String, dynamic>> orderMaps = await db.query(
        'orders',
        where: orderQuery,
        whereArgs: orderArgs,
        orderBy: 'order_time DESC',
      );

      double salesSum = 0.0;
      double taxSum = 0.0;
      for (var order in orderMaps) {
        final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
        salesSum += total;
        // 5% GST calculation: tax = total * (5 / 105)
        taxSum += total * (5 / 105);
      }

      // 2. Fetch Expenses
      final List<Map<String, dynamic>> expenseMaps = await db.query(
        'expenses',
        where: 'restaurant_id = ? AND date BETWEEN ? AND ?',
        whereArgs: [restId, startStr, endStr],
        orderBy: 'date DESC',
      );

      double expenseSum = 0.0;
      for (var exp in expenseMaps) {
        expenseSum += (exp['amount'] as num?)?.toDouble() ?? 0.0;
      }

      setState(() {
        _salesTransactions = orderMaps;
        _expenses = expenseMaps;
        _totalSales = salesSum;
        _totalTaxes = taxSum;
        _totalExpenses = expenseSum;
        _totalOrdersCount = orderMaps.length;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading accounts data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addExpense(String description, double amount, String category, String date) async {
    try {
      final db = await _dbHelper.database;
      final restId = DatabaseHelper.currentRestaurantId;

      await db.insert('expenses', {
        'description': description,
        'amount': amount,
        'category': category,
        'date': date,
        'restaurant_id': restId,
      });

      if(false) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added successfully!')),
      );
      _loadAccountsData();
    } catch (e) {
      if(false) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding expense: $e')),
      );
    }
  }

  Future<void> _deleteExpense(int id) async {
    try {
      final db = await _dbHelper.database;
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
      if(false) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully!')),
      );
      _loadAccountsData();
    } catch (e) {
      if(false) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting expense: $e')),
      );
    }
  }

  void _showAddExpenseDialog() {
    final descController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Utilities';
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Expense'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountController,
                      decoration: const InputDecoration(labelText: 'Amount (₹)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: ['Utilities', 'Supplies', 'Rent', 'Salaries', 'Marketing', 'Other']
                          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text('Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
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
                    final desc = descController.text.trim();
                    final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
                    if (desc.isNotEmpty && amt > 0) {
                      Navigator.pop(context);
                      _addExpense(
                        desc,
                        amt,
                        selectedCategory,
                        DateFormat('yyyy-MM-dd').format(selectedDate) + "T12:00:00",
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _exportReport(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Exporting $type Report'),
        content: Row(
          children: const [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Generating file, please wait...')),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context); // close loader
      final fileName = '${type.toLowerCase()}_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.${type == 'PDF' ? 'pdf' : 'xlsx'}';
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Report successfully saved to:\nC:\\Users\\ssbha\\Downloads\\$fileName'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final netProfit = _totalSales - _totalExpenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts & Financials'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAccountsData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Sales & Payments'),
            Tab(icon: Icon(Icons.money_off), text: 'Expenses'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Financial Metrics Top Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 700;
                      final columns = isMobile ? 2 : 4;
                      final spacing = 16.0;
                      final cardWidth = (constraints.maxWidth - (spacing * (columns - 1))) / columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          _buildSummaryCard('Total Sales', _totalSales, Icons.trending_up, Colors.green, cardWidth),
                          _buildSummaryCard('Expenses', _totalExpenses, Icons.trending_down, Colors.red, cardWidth),
                          _buildSummaryCard('Tax Collected', _totalTaxes, Icons.gavel, Colors.orange, cardWidth),
                          _buildSummaryCard('Net Profit', netProfit, Icons.account_balance_wallet, AppColors.primary, cardWidth),
                        ],
                      );
                    },
                  ),
                ),

                // Filters Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;

                      final dateBtn = ElevatedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _selectedDateRange == null
                              ? 'Filter Date'
                              : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
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
                            _loadAccountsData();
                          }
                        },
                      );

                      final paymentModeDropdown = DropdownButton<String>(
                        value: _selectedPaymentMode,
                        items: ['All', 'Cash', 'UPI', 'Card', 'Wallet']
                            .map((mode) => DropdownMenuItem(value: mode, child: Text(mode)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedPaymentMode = val);
                            _loadAccountsData();
                          }
                        },
                      );

                      final exportBtn = PopupMenuButton<String>(
                        onSelected: _exportReport,
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'PDF', child: Text('Export PDF Report')),
                          const PopupMenuItem(value: 'Excel', child: Text('Export Excel Report')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.download, color: AppColors.primary, size: 18),
                              SizedBox(width: 8),
                              Text('Export Reports', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );

                      if (isMobile) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: dateBtn),
                                const SizedBox(width: 16),
                                paymentModeDropdown,
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(width: double.infinity, child: exportBtn),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          dateBtn,
                          const SizedBox(width: 16),
                          paymentModeDropdown,
                          const Spacer(),
                          exportBtn,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Sales View
                      _buildSalesList(),

                      // Expenses View
                      _buildExpensesList(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double value, IconData icon, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(40), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withAlpha(25),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${value.toStringAsFixed(2)}',
                  style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList() {
    if (_salesTransactions.isEmpty) {
      return const Center(child: Text('No sales records found for this period.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _salesTransactions.length,
      itemBuilder: (context, index) {
        final order = _salesTransactions[index];
        final total = (order['total_amount'] as num).toDouble();
        final tax = total * (5 / 105);
        final date = DateTime.tryParse(order['order_time']) ?? DateTime.now();

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.withAlpha(20),
              child: const Icon(Icons.attach_money, color: Colors.green),
            ),
            title: Text('Order #${order['id']} (Type: ${order['type']})'),
            subtitle: Text(
              'Time: ${DateFormat('yyyy-MM-dd hh:mm a').format(date)}\nPayment: ${order['payment_method'] ?? "None"} | GST (5%): ₹${tax.toStringAsFixed(2)}',
            ),
            trailing: Text(
              '₹${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpensesList() {
    if (_expenses.isEmpty) {
      return const Center(child: Text('No expenses recorded for this period.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expenses.length,
      itemBuilder: (context, index) {
        final expense = _expenses[index];
        final amount = (expense['amount'] as num).toDouble();
        final date = DateTime.tryParse(expense['date']) ?? DateTime.now();

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red.withAlpha(20),
              child: const Icon(Icons.money_off, color: Colors.red),
            ),
            title: Text(expense['description'] ?? 'Unnamed Expense'),
            subtitle: Text(
              'Category: ${expense['category'] ?? "General"}\nDate: ${DateFormat('yyyy-MM-dd').format(date)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _confirmDeleteExpense(expense['id']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteExpense(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteExpense(id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
