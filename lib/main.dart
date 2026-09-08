import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/branch_selection_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/orders_history_screen.dart';
import 'screens/products_management_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/tables_screen.dart';
import 'screens/kitchen_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/user_management_screen.dart';
import 'screens/printer_settings_screen.dart';
import 'screens/restaurants_screen.dart';
import 'screens/menu_card_screen.dart';
import 'screens/live_tracking_screen.dart';
import 'screens/waiter_order_screen.dart';
import 'services/server_service.dart';
import 'services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerService.instance.startServer();
  await SyncService.instance.initConnection();
  
  final prefs = await SharedPreferences.getInstance();
  final rememberMe = prefs.getBool('remember_me') ?? false;
  if (!rememberMe) {
    await prefs.remove('token');
  }
  final hasToken = (prefs.getString('token') != null) && rememberMe;

  final themeStr = prefs.getString('theme_mode') ?? 'light';
  if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else if (themeStr == 'system') {
    themeNotifier.value = ThemeMode.system;
  } else {
    themeNotifier.value = ThemeMode.light;
  }
  
  runApp(MyApp(hasToken: hasToken));
}

GoRouter _buildRouter(bool hasToken) {
  return GoRouter(
    initialLocation: hasToken ? '/branch_selection' : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/branch_selection',
        builder: (context, state) => const BranchSelectionScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return DashboardScreen(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const OverviewScreen(),
          ),
          GoRoute(
            path: '/dashboard/pos',
            builder: (context, state) {
              final orderId = state.uri.queryParameters['orderId'];
              final tableId = state.uri.queryParameters['tableId'];
              return PosScreen(
                reopenOrderId: orderId != null ? int.tryParse(orderId) : null,
                selectedTableId: tableId != null ? int.tryParse(tableId) : null,
              );
            },
          ),
          GoRoute(
            path: '/dashboard/orders',
            builder: (context, state) => const OrdersHistoryScreen(),
          ),
          GoRoute(
            path: '/dashboard/products_manage',
            builder: (context, state) => const ProductsManagementScreen(),
          ),
          GoRoute(
            path: '/dashboard/accounts',
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/dashboard/tables',
            builder: (context, state) => const TablesScreen(),
          ),
          GoRoute(
            path: '/dashboard/waiter_order',
            builder: (context, state) => const WaiterOrderScreen(),
          ),
          GoRoute(
            path: '/dashboard/kitchen',
            builder: (context, state) => const KitchenScreen(),
          ),
          GoRoute(
            path: '/dashboard/live_tracking',
            builder: (context, state) => const LiveTrackingScreen(),
          ),
          GoRoute(
            path: '/dashboard/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/dashboard/analytics',
            builder: (context, state) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/dashboard/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/dashboard/user_management',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/dashboard/menu_card',
            builder: (context, state) => const MenuCardScreen(),
          ),
          GoRoute(
            path: '/dashboard/printer_settings',
            builder: (context, state) => const PrinterSettingsScreen(),
          ),
          GoRoute(
            path: '/dashboard/restaurants',
            builder: (context, state) => const RestaurantsScreen(),
          ),
        ],
      ),
    ],
  );
}

class MyApp extends StatefulWidget {
  final bool hasToken;
  const MyApp({super.key, required this.hasToken});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(widget.hasToken);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp.router(
          title: 'Dine Master',
          debugShowCheckedModeBanner: false,
          themeMode: currentThemeMode,
          theme: ThemeData(
            useMaterial3: true,
            primarySwatch: AppColors.primaryMaterialColor,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              primary: AppColors.primary,
              secondary: AppColors.secondary,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: AppColors.background,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.black),
            ),
            cardTheme: const CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primarySwatch: AppColors.primaryMaterialColor,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              primary: AppColors.primary,
              secondary: AppColors.secondary,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF14141E),
            appBarTheme: AppBarTheme(
              elevation: 0,
              backgroundColor: Colors.grey.shade900,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              color: Colors.grey.shade900,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          routerConfig: _router,
        );
      },
    );
  }
}
