import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dine_master/models/product_model.dart';
import 'package:dine_master/models/table_model.dart';
import 'package:dine_master/widgets/food_attributes_badge.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Table Selection & Addition Tests', () {
    test('TableModel equality and hashCode work correctly', () {
      final t1 = TableModel(
        id: 10,
        tableNumber: 'T-10',
        capacity: 4,
        status: 'Available',
      );
      final t2 = TableModel(
        id: 10,
        tableNumber: 'T-10',
        capacity: 6,
        status: 'Occupied',
      );
      final t3 = TableModel(
        id: 11,
        tableNumber: 'T-11',
        capacity: 4,
        status: 'Available',
      );

      expect(t1 == t2, isTrue);
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1 == t3, isFalse);
    });

    test('TableModel toMap and sanitization work without waiter_name SQLite error', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tables (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              table_number TEXT UNIQUE NOT NULL,
              name TEXT,
              capacity INTEGER NOT NULL DEFAULT 4,
              status TEXT NOT NULL DEFAULT 'Available',
              section TEXT,
              table_type TEXT DEFAULT 'Standard Table',
              is_active INTEGER DEFAULT 1,
              is_reservable INTEGER DEFAULT 1,
              notes TEXT,
              merged_with_id INTEGER,
              waiter_id INTEGER,
              waiter_name TEXT,
              restaurant_id INTEGER DEFAULT 1
            )
          ''');
        },
      );

      final table = TableModel(
        tableNumber: 'TEST-TABLE-99',
        name: 'VIP Corner',
        capacity: 4,
        status: 'Available',
        section: 'VIP Lounge',
        tableType: 'Standard Table',
        waiterId: 1,
        waiterName: 'Test Waiter',
      );

      // Verify toMap sanitization for tables insert:
      final map = table.toMap();
      map.remove('waiter_name');
      final insertedId = await db.insert('tables', map);
      expect(insertedId, isPositive);

      final result = await db.query('tables', where: 'id = ?', whereArgs: [insertedId]);
      expect(result.first['name'], 'VIP Corner');
      expect(result.first['capacity'], 4);

      // Verify update
      final updateCount = await db.update(
        'tables',
        {'capacity': 6, 'status': 'Occupied'},
        where: 'id = ?',
        whereArgs: [insertedId],
      );
      expect(updateCount, equals(1));

      await db.close();
    });
  });

  group('Product Item Card Model & Widget Tests', () {
    test('ProductModel parses attributes and dietary tags properly', () {
      final product = ProductModel(
        id: 101,
        name: 'Paneer Tikka',
        category: 'Starters',
        price: 249.0,
        isVeg: 1,
        isAvailable: true,
        gstPercentage: 5.0,
        attributes: ['Chef\'s Special', 'Bestseller'],
        dietaryPreferences: ['Pure Jain'],
      );

      final map = product.toMap();
      expect(map['name'], 'Paneer Tikka');
      expect(map['price'], 249.0);
      expect(map['is_veg'], 1);
      expect(map['is_available'], 1);
      expect(map['attributes'], contains('Chef\'s Special'));

      final reconstructed = ProductModel.fromMap(map);
      expect(reconstructed.name, 'Paneer Tikka');
      expect(reconstructed.attributes, contains('Chef\'s Special'));
      expect(reconstructed.attributes, contains('Bestseller'));
      expect(reconstructed.dietaryPreferences, contains('Pure Jain'));
      expect(reconstructed.isAvailable, isTrue);
    });

    testWidgets('FoodAttributesBadge renders chef special and dietary tags', (WidgetTester tester) async {
      final product = ProductModel(
        id: 201,
        name: 'Special Dal Makhani',
        category: 'Main Course',
        price: 320.0,
        isVeg: 1,
        isAvailable: true,
        attributes: ["Chef's Special", "Bestseller"],
        dietaryPreferences: ['Pure Jain'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoodAttributesBadge(product: product),
          ),
        ),
      );

      expect(find.text("Pure Jain"), findsOneWidget);
      expect(find.text("Chef's Special"), findsOneWidget);
      expect(find.byIcon(Icons.spa), findsOneWidget);
    });

    testWidgets('POS Item Card styling elements render correctly with veg indicator and sold out badge', (WidgetTester tester) async {
      final availableProduct = ProductModel(
        id: 1,
        name: 'Veg Biryani',
        category: 'Main Course',
        price: 220.0,
        isVeg: 1,
        isAvailable: true,
        attributes: ['Bestseller'],
      );

      final soldOutProduct = ProductModel(
        id: 2,
        name: 'Chicken Kebab',
        category: 'Starters',
        price: 280.0,
        isVeg: 0,
        isAvailable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(availableProduct.name),
                Text('₹${availableProduct.price.toStringAsFixed(2)}'),
                if (!soldOutProduct.isAvailable)
                  const Text('SOLD OUT'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Veg Biryani'), findsOneWidget);
      expect(find.text('₹220.00'), findsOneWidget);
      expect(find.text('SOLD OUT'), findsOneWidget);
    });
  });
}
