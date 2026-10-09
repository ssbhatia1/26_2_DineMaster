import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dine_master/models/product_model.dart';
import 'package:dine_master/widgets/pos_item_card.dart';
import 'package:dine_master/screens/waiter/components/waiter_menu_view.dart';
import 'package:dine_master/screens/waiter/waiter_models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PosItemCard Widget Parity & Functionality Tests', () {
    testWidgets('PosItemCard renders standard POS styling, price, and category pill', (WidgetTester tester) async {
      final product = ProductModel(
        id: 1,
        name: 'Butter Naan',
        category: 'Breads',
        price: 45.0,
        isVeg: 1,
        isAvailable: true,
      );

      bool tapped = false;
      bool infoTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 240,
              child: PosItemCard(
                product: product,
                onTap: () => tapped = true,
                onInfoTap: () => infoTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Butter Naan'), findsOneWidget);
      expect(find.text('₹45.0'), findsOneWidget);
      expect(find.text('Breads'), findsOneWidget);
      expect(find.byIcon(Icons.local_pizza), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      // Verify tap behavior
      await tester.tap(find.text('Butter Naan'));
      expect(tapped, isTrue);

      await tester.tap(find.byIcon(Icons.info_outline));
      expect(infoTapped, isTrue);
    });

    testWidgets('PosItemCard displays in-cart count badge when inCartCount > 0', (WidgetTester tester) async {
      final product = ProductModel(
        id: 2,
        name: 'Veg Platter',
        category: 'Starters',
        price: 320.0,
        isVeg: 1,
        isAvailable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 240,
              child: PosItemCard(
                product: product,
                inCartCount: 3,
              ),
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('PosItemCard displays SOLD OUT overlay and disables tap when unavailable', (WidgetTester tester) async {
      final unavailableProduct = ProductModel(
        id: 3,
        name: 'Mutton Curry',
        category: 'Main Course',
        price: 450.0,
        isVeg: 0,
        isAvailable: false,
      );

      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 240,
              child: PosItemCard(
                product: unavailableProduct,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('SOLD OUT'), findsOneWidget);
      expect(find.byIcon(Icons.lunch_dining), findsOneWidget);

      await tester.tap(find.text('Mutton Curry'), warnIfMissed: false);
      expect(tapped, isFalse);
    });
  });

  group('Take Order (WaiterMenuView) Grid & Card Reusability Tests', () {
    testWidgets('WaiterMenuView renders PosItemCard with matching POS grid spacing', (WidgetTester tester) async {
      final products = [
        ProductModel(
          id: 10,
          name: 'Paneer Tikka',
          category: 'Starters',
          price: 250.0,
          isVeg: 1,
          isAvailable: true,
        ),
        ProductModel(
          id: 11,
          name: 'Crispy Corn',
          category: 'Starters',
          price: 180.0,
          isVeg: 1,
          isAvailable: true,
        ),
      ];

      final cartItems = [
        WaiterCartItem(product: products[0], quantity: 2),
      ];

      ProductModel? tappedProduct;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: WaiterMenuView(
                categories: const ['All', 'Starters'],
                selectedCategory: 'Starters',
                onCategorySelected: (_) {},
                filteredProducts: products,
                cartItems: cartItems,
                onProductTap: (prod) => tappedProduct = prod,
              ),
            ),
          ),
        ),
      );

      // Verify PosItemCards rendered
      expect(find.byType(PosItemCard), findsNWidgets(2));
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('Crispy Corn'), findsOneWidget);

      // Verify in-cart badge for Paneer Tikka (quantity 2)
      expect(find.text('2'), findsOneWidget);

      // Verify grid delegate spacing matches POS Billing
      final gridView = tester.widget<GridView>(find.byType(GridView));
      final delegate = gridView.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(delegate.maxCrossAxisExtent, equals(220));
      expect(delegate.crossAxisSpacing, equals(10));
      expect(delegate.mainAxisSpacing, equals(10));
      expect(delegate.childAspectRatio, equals(0.85));

      // Tap card
      await tester.tap(find.text('Crispy Corn'));
      expect(tappedProduct?.id, equals(11));
    });
  });

  group('Dummy Data Removal Tests', () {
    test('Dummy data cleanup removes sample records and preserves defaults', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL, category TEXT, is_veg INTEGER, is_available INTEGER DEFAULT 1, restaurant_id INTEGER)');
          await db.execute('CREATE TABLE tables (id INTEGER PRIMARY KEY, table_number TEXT, name TEXT, capacity INTEGER, status TEXT, restaurant_id INTEGER)');
          await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, username TEXT, password TEXT, role TEXT, is_active INTEGER DEFAULT 1, created_at TEXT)');
          await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT UNIQUE, restaurant_id INTEGER)');
        },
      );

      // Seed dummy records
      await db.insert('products', {'name': 'Paneer Butter Masala', 'price': 250.0, 'category': 'Main Course', 'is_veg': 1});
      await db.insert('products', {'name': 'Chicken Biryani', 'price': 300.0, 'category': 'Main Course', 'is_veg': 0});
      await db.insert('products', {'name': 'Garlic Naan', 'price': 50.0, 'category': 'Breads', 'is_veg': 1});
      await db.insert('products', {'name': 'Cold Coffee', 'price': 120.0, 'category': 'Beverages', 'is_veg': 1});
      await db.insert('products', {'name': 'Real Customer Dish', 'price': 199.0, 'category': 'Starters', 'is_veg': 1});

      for (int i = 1; i <= 10; i++) {
        await db.insert('tables', {'table_number': 'T$i', 'name': null, 'capacity': 4, 'status': 'Available'});
      }
      await db.insert('tables', {'table_number': 'TABLE-CUSTOM', 'name': 'Booth 1', 'capacity': 6, 'status': 'Available'});

      await db.insert('users', {'name': 'Manager User', 'username': 'manager', 'role': 'Manager'});
      await db.insert('users', {'name': 'Cashier User', 'username': 'cashier', 'role': 'Cashier'});
      await db.insert('users', {'name': 'Owner User', 'username': 'owner', 'role': 'Owner'});

      // Run dummy removal logic
      final dummyProductNames = ['Paneer Butter Masala', 'Chicken Biryani', 'Garlic Naan', 'Cold Coffee'];
      for (final name in dummyProductNames) {
        await db.delete('products', where: 'name = ?', whereArgs: [name]);
      }
      for (int i = 1; i <= 10; i++) {
        await db.delete('tables', where: 'table_number = ? AND (name IS NULL OR name = \'\')', whereArgs: ['T$i']);
      }
      final dummyUsernames = ['manager', 'cashier', 'john_waiter', 'sarah_waiter', 'chef_marco', 'chef_priya'];
      for (final uname in dummyUsernames) {
        await db.delete('users', where: 'username = ?', whereArgs: [uname]);
      }

      // Verify dummy records are gone
      final prods = await db.query('products');
      expect(prods.length, equals(1));
      expect(prods.first['name'], equals('Real Customer Dish'));

      final tables = await db.query('tables');
      expect(tables.length, equals(1));
      expect(tables.first['table_number'], equals('TABLE-CUSTOM'));

      final users = await db.query('users');
      expect(users.length, equals(1));
      expect(users.first['username'], equals('owner'));

      await db.close();
    });
  });
}
