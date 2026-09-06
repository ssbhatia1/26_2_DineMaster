import 'dart:ui';
import 'package:nexodine/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';

class DashboardScreen extends StatefulWidget {
  final Widget child;
  const DashboardScreen({super.key, required this.child});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  int? _selectedRestaurantId;
  String _username = 'User';

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? 'User';
    });
  }

  Future<void> _loadRestaurants() async {
    final db = await DatabaseHelper.instance.database;
    final restaurants = await db.query('restaurants');
    setState(() {
      _restaurants = restaurants;
      if (restaurants.isNotEmpty) {
        _selectedRestaurantId = DatabaseHelper.currentRestaurantId ?? (restaurants.first['id'] as int);
        DatabaseHelper.currentRestaurantId = _selectedRestaurantId;
      }
    });
  }

  final List<Map<String, dynamic>> _navItems = [
    // --- Overview ---
    {
      'icon': Icons.dashboard_outlined,
      'selectedIcon': Icons.dashboard,
      'label': 'Dashboard',
      'route': '/dashboard',
      'category': 'Overview'
    },
    // --- Operations ---
    {
      'icon': Icons.table_bar_outlined,
      'selectedIcon': Icons.table_bar,
      'label': 'Tables',
      'route': '/dashboard/tables',
      'category': 'Operations'
    },
    {
      'icon': Icons.assignment_turned_in_outlined,
      'selectedIcon': Icons.assignment_turned_in,
      'label': 'Waiter Ordering',
      'route': '/dashboard/waiter_order',
      'category': 'Operations'
    },
    {
      'icon': Icons.kitchen_outlined,
      'selectedIcon': Icons.kitchen,
      'label': 'Kitchen KOT',
      'route': '/dashboard/kitchen',
      'category': 'Operations'
    },
    {
      'icon': Icons.track_changes,
      'selectedIcon': Icons.track_changes,
      'label': 'Live Tracking',
      'route': '/dashboard/live_tracking',
      'category': 'Operations'
    },
    // --- Billing ---
    {
      'icon': Icons.point_of_sale_outlined,
      'selectedIcon': Icons.point_of_sale,
      'label': 'POS Billing',
      'route': '/dashboard/pos',
      'category': 'Billing'
    },
    {
      'icon': Icons.history_outlined,
      'selectedIcon': Icons.history,
      'label': 'Order History',
      'route': '/dashboard/orders',
      'category': 'Billing'
    },
    // --- Management ---
    {
      'icon': Icons.restaurant_menu_outlined,
      'selectedIcon': Icons.restaurant_menu,
      'label': 'Food Products',
      'route': '/dashboard/products_manage',
      'category': 'Management'
    },
    {
      'icon': Icons.menu_book_outlined,
      'selectedIcon': Icons.menu_book,
      'label': 'Menu Card',
      'route': '/dashboard/menu_card',
      'category': 'Management'
    },
    {
      'icon': Icons.inventory_2_outlined,
      'selectedIcon': Icons.inventory,
      'label': 'Inventory',
      'route': '/dashboard/inventory',
      'category': 'Management'
    },
    {
      'icon': Icons.account_balance_outlined,
      'selectedIcon': Icons.account_balance,
      'label': 'Accounts',
      'route': '/dashboard/accounts',
      'category': 'Management'
    },
    // --- Admin ---
    {
      'icon': Icons.analytics_outlined,
      'selectedIcon': Icons.analytics,
      'label': 'Analytics',
      'route': '/dashboard/analytics',
      'category': 'Admin'
    },
    {
      'icon': Icons.restaurant_outlined,
      'selectedIcon': Icons.restaurant,
      'label': 'Restaurants',
      'route': '/dashboard/restaurants',
      'category': 'Admin'
    },
    {
      'icon': Icons.settings_outlined,
      'selectedIcon': Icons.settings,
      'label': 'Settings',
      'route': '/dashboard/settings',
      'category': 'Admin'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final String location = GoRouterState.of(context).uri.path;
    
    int activeIndex = _navItems.indexWhere((item) => item['route'] == location);
    if (activeIndex == -1) {
      int bestMatchLength = 0;
      for (int i = 0; i < _navItems.length; i++) {
        final route = _navItems[i]['route'] as String;
        if (location.startsWith(route) && route.length > bestMatchLength) {
          bestMatchLength = route.length;
          activeIndex = i;
        }
      }
    }
    if (activeIndex == -1) activeIndex = 0;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) ...[
            // Sidebar for Desktop
            Container(
              width: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E1E2F),
                    Color(0xFF0F0F1A),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // App Brand
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/logo.jpg',
                          height: 40,
                          width: 40,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DINE MASTER',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              'Hi, $_username',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  
                  // Nav Items
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: _buildNavSections(context, activeIndex),
                    ),
                  ),

                  // User Profile
                  const Divider(color: Colors.white12, height: 1),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, color: AppColors.primary),
                    ),
                    title: const Text(
                      'Owner Account',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'System Admin',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('token');
                        await prefs.remove('username');
                        context.go('/');
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
          
          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top App Bar
                AppBar(
                  title: Text(
                    _navItems[activeIndex]['label'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  actions: [
                    if (_restaurants.isNotEmpty)
                      DropdownButton<int>(
                        value: _selectedRestaurantId,
                        underline: const SizedBox(),
                        items: _restaurants.map((r) {
                          return DropdownMenuItem<int>(
                            value: r['id'],
                            child: Text(r['name']),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRestaurantId = value;
                            DatabaseHelper.currentRestaurantId = value;
                          });

                        },
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.notifications),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.dark_mode),
                      onPressed: () {},
                    ),
                    if (!isDesktop)
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () {
                          context.go('/');
                        },
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                
                // Content
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    child: KeyedSubtree(
                      key: ValueKey(DatabaseHelper.currentRestaurantId),
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? BottomNavigationBar(
              currentIndex: activeIndex >= 5 ? 0 : activeIndex,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.primaryMaterialColor[900]!,
              unselectedItemColor: Colors.grey,
              onTap: (index) {
                context.go(_navItems[index]['route']);
              },
              items: _navItems
                  .take(5) // Only show first 5 on mobile bottom nav
                  .map((item) => BottomNavigationBarItem(
                        icon: Icon(item['icon']),
                        label: item['label'],
                      ))
                  .toList(),
            )
          : null,
    );
  }

  List<Widget> _buildNavSections(BuildContext context, int activeIndex) {
    final Map<String, List<int>> categories = {};
    for (int i = 0; i < _navItems.length; i++) {
      final cat = _navItems[i]['category'] ?? 'General';
      categories.putIfAbsent(cat, () => []).add(i);
    }

    final List<Widget> widgets = [];
    categories.forEach((categoryName, indices) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 16, bottom: 8),
          child: Text(
            categoryName.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );

      for (final index in indices) {
        final item = _navItems[index];
        final isSelected = activeIndex == index;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: Icon(
                isSelected ? item['selectedIcon'] : item['icon'],
                color: isSelected ? Colors.white : Colors.white60,
                size: 20,
              ),
              title: Text(
                item['label'],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedTileColor: Colors.white.withAlpha(25),
              onTap: () {
                context.go(item['route']);
              },
            ),
          ),
        );
      }
    });

    return widgets;
  }
}
