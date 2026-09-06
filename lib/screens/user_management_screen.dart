import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import '../services/sync_service.dart';
import 'dart:async';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _obscurePassword = true;
  String _searchQuery = '';
  late TabController _tabController;
  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUsers();

    // Subscribe to database changes to sync in real time across screens
    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted) {
        _loadUsers();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final users = await db.query('users', orderBy: 'name ASC');
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showUserDialog([Map<String, dynamic>? user]) {
    _obscurePassword = true;
    final isEditing = user != null;
    final nameController = TextEditingController(text: isEditing ? user['name'] : '');
    final usernameController = TextEditingController(text: isEditing ? user['username'] : '');
    // Prefill edit password with placeholder
    final passwordController = TextEditingController(text: isEditing ? '********' : '');
    final contactController = TextEditingController(text: isEditing ? (user['contact_details'] ?? '') : '');
    final shiftController = TextEditingController(text: isEditing ? (user['shift_timing'] ?? '') : '');
    
    String role = isEditing ? user['role'] : 'Waiter';
    bool isActive = isEditing ? (user['is_active'] == 1) : true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(isEditing ? Icons.edit_outlined : Icons.person_add_alt_1_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(isEditing ? 'Edit Employee Profile' : 'Add New Employee'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  enabled: !isEditing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: isEditing ? 'Password (Leave as-is to keep old)' : 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setStateDialog(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  items: ['Owner', 'Manager', 'Cashier', 'Waiter', 'Chef']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) => setStateDialog(() => role = val!),
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.work_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contactController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Details',
                    hintText: 'e.g. +91 98765 43210',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shiftController,
                  decoration: const InputDecoration(
                    labelText: 'Shift Timing',
                    hintText: 'e.g. 09:00 AM - 05:00 PM',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Status (Active)'),
                  value: isActive,
                  activeColor: Colors.green,
                  onChanged: (val) => setStateDialog(() => isActive = val),
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
              onPressed: () async {
                final name = nameController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();
                final contact = contactController.text.trim();
                final shift = shiftController.text.trim();

                if (name.isEmpty || username.isEmpty || password.isEmpty) {
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill name, username, and password')),
                  );
                  return;
                }

                final db = await DatabaseHelper.instance.database;
                
                final Map<String, dynamic> data = {
                  'name': name,
                  'role': role,
                  'is_active': isActive ? 1 : 0,
                  'contact_details': contact,
                  'shift_timing': shift,
                };

                // Hash password if edited/new
                if (!isEditing) {
                  data['username'] = username;
                  data['password'] = DatabaseHelper.hashPassword(password);
                  data['created_at'] = DateTime.now().toIso8601String();
                  await db.insert('users', data);
                } else {
                  if (password != '********') {
                    data['password'] = DatabaseHelper.hashPassword(password);
                  }
                  await db.update('users', data, where: 'id = ?', whereArgs: [user['id']]);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEditing ? 'Employee profile updated' : 'Employee added successfully')),
                  );
                }
                _loadUsers();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: Text(isEditing ? 'Save Changes' : 'Add Employee'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(int id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text('Are you sure you want to delete employee "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final db = await DatabaseHelper.instance.database;
                await db.delete('users', where: 'id = ?', whereArgs: [id]);
                if (context.mounted) {
                  Navigator.pop(context);
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Employee removed successfully')),
                  );
                }
                _loadUsers();
              } catch (e) {
                print('Error deleting user: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeList(List<Map<String, dynamic>> list) {
    final filtered = list.where((emp) {
      final name = (emp['name'] as String? ?? '').toLowerCase();
      final username = (emp['username'] as String? ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || username.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty 
                  ? 'No staff members registered in this category'
                  : 'No staff members match "$_searchQuery"', 
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final emp = filtered[index];
        final bool isActive = emp['is_active'] == 1;
        final name = emp['name'] as String? ?? 'N/A';
        final username = emp['username'] as String? ?? '';
        final role = emp['role'] as String? ?? '';
        final contact = emp['contact_details'] as String? ?? '';
        final shift = emp['shift_timing'] as String? ?? '';

        // Initials and gradient colors
        final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S';
        final List<Color> avatarGradient = isActive 
            ? [AppColors.primary, Colors.indigo] 
            : [Colors.grey, Colors.blueGrey];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade100, width: 1.5),
          ),
          color: isDark ? Colors.grey.shade900 : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with modern gradient
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: avatarGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: avatarGradient.first.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Premium badge status
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$username  |  $role',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 14, color: AppColors.primaryMaterialColor[300]!),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              contact.isNotEmpty ? contact : 'No contact details',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w400),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule_outlined, size: 14, color: AppColors.primaryMaterialColor[300]!),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              shift.isNotEmpty ? shift : 'No shift assigned',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w400),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action options
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                      onPressed: () => _showUserDialog(emp),
                      // tooltip disabled,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => _confirmDelete(emp['id'], name),
                      // tooltip disabled,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Filtered users by role
    final chefs = _users.where((u) => u['role'] == 'Chef').toList();
    final waiters = _users.where((u) => u['role'] == 'Waiter').toList();
    final otherStaff = _users.where((u) => u['role'] != 'Chef' && u['role'] != 'Waiter').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff & User Onboarding', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: isDark ? null : Colors.white,
          foregroundColor: isDark ? null : Colors.black,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.restaurant), text: 'Chefs'),
              Tab(icon: Icon(Icons.directions_walk), text: 'Waiters'),
              Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'Other Staff'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  // Sleek Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search staff by name or username...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                        fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildEmployeeList(chefs),
                        _buildEmployeeList(waiters),
                        _buildEmployeeList(otherStaff),
                      ],
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showUserDialog(),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Onboard Staff', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
