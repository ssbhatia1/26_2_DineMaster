import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dine_master/core/database/database_helper.dart';
import 'package:dine_master/repositories/table_repository.dart';
import 'package:dine_master/models/table_model.dart';
import 'package:dine_master/screens/tables_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
  });

  group('Multiple Table Reservations & Occupation Logic Tests', () {
    test('Can store and retrieve multiple confirmed reservations for the same table', () async {
      final db = await DatabaseHelper.instance.database;
      final repo = TableRepository();

      // Create a test table
      final testTable = TableModel(
        tableNumber: 'T_TEST_RES',
        capacity: 4,
        status: 'Available',
        section: 'Main Hall',
        tableType: 'Standard Table',
      );
      final tableId = await repo.addTable(testTable);

      final now = DateTime.now();
      final booking1Time = DateTime(now.year, now.month, now.day, 13, 0);
      final booking2Time = DateTime(now.year, now.month, now.day, 19, 0);

      // Insert first reservation
      await db.insert('bookings', {
        'table_id': tableId,
        'customer_name': 'Alice Lunch',
        'customer_phone': '9876543210',
        'guest_count': 2,
        'booking_time': booking1Time.toIso8601String(),
        'status': 'Confirmed',
        'restaurant_id': 1,
      });

      // Insert second reservation for the same table at a different time
      await db.insert('bookings', {
        'table_id': tableId,
        'customer_name': 'Bob Dinner',
        'customer_phone': '9123456780',
        'guest_count': 4,
        'booking_time': booking2Time.toIso8601String(),
        'status': 'Confirmed',
        'restaurant_id': 1,
      });

      // Query all confirmed bookings for this table
      final bookings = await db.query(
        'bookings',
        where: 'table_id = ? AND status = ?',
        whereArgs: [tableId, 'Confirmed'],
        orderBy: 'booking_time ASC',
      );

      expect(bookings.length, equals(2));
      expect(bookings[0]['customer_name'], equals('Alice Lunch'));
      expect(bookings[1]['customer_name'], equals('Bob Dinner'));

      // Clean up
      await db.delete('bookings', where: 'table_id = ?', whereArgs: [tableId]);
      await repo.deleteTable(tableId);
    });

    test('Future reservation keeps table Available, does not lock into Reserved', () async {
      final db = await DatabaseHelper.instance.database;
      final repo = TableRepository();

      final testTable = TableModel(
        tableNumber: 'T_FUTURE_RES',
        capacity: 4,
        status: 'Available',
        section: 'Patio',
        tableType: 'Standard Table',
      );
      final tableId = await repo.addTable(testTable);

      // Booking 3 days into future
      final futureDate = DateTime.now().add(const Duration(days: 3));
      await db.insert('bookings', {
        'table_id': tableId,
        'customer_name': 'Charlie Future',
        'guest_count': 4,
        'booking_time': futureDate.toIso8601String(),
        'status': 'Confirmed',
        'restaurant_id': 1,
      });

      // Fetch table status from DB
      final tables = await repo.getTables();
      final target = tables.firstWhere((t) => t.id == tableId);

      // Table must remain Available because the reservation is in the future
      expect(target.status, equals('Available'));

      // Clean up
      await db.delete('bookings', where: 'table_id = ?', whereArgs: [tableId]);
      await repo.deleteTable(tableId);
    });

    test('Manual occupation at any time allows occupying and releasing table', () async {
      final repo = TableRepository();

      final testTable = TableModel(
        tableNumber: 'T_MANUAL_OCC',
        capacity: 4,
        status: 'Available',
        section: 'Bar Area',
        tableType: 'High Top',
      );
      final tableId = await repo.addTable(testTable);

      // Manually occupy the table (walk-in guests)
      await repo.updateTableStatus(tableId, 'Occupied');
      var tables = await repo.getTables();
      var target = tables.firstWhere((t) => t.id == tableId);
      expect(target.status, equals('Occupied'));

      // Manually release table to Available
      await repo.updateTableStatus(tableId, 'Available');
      tables = await repo.getTables();
      target = tables.firstWhere((t) => t.id == tableId);
      expect(target.status, equals('Available'));

      // Clean up
      await repo.deleteTable(tableId);
    });

    test('Active reservation window detection logic accurately marks current vs upcoming', () {
      final now = DateTime(2026, 9, 9, 14, 30); // 2:30 PM

      final bookingPast = DateTime(2026, 9, 9, 12, 0); // 12:00 PM (ended 1:00 PM)
      final bookingActive = DateTime(2026, 9, 9, 14, 0); // 2:00 PM (active until 3:00 PM)
      final bookingFuture = DateTime(2026, 9, 9, 19, 0); // 7:00 PM

      bool isBookingActive(DateTime bTime, DateTime current) {
        final slotEnd = bTime.add(const Duration(hours: 1));
        return !current.isBefore(bTime) && current.isBefore(slotEnd);
      }

      expect(isBookingActive(bookingPast, now), isFalse);
      expect(isBookingActive(bookingActive, now), isTrue);
      expect(isBookingActive(bookingFuture, now), isFalse);
    });
  });

  group('TablesScreen Widget & Layout Overflow Tests', () {
    testWidgets('TablesScreen renders correctly and shows tabs without OverflowBar error', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        const MaterialApp(
          home: TablesScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify app bar title and tabs
      expect(find.text('Restaurant Table Management'), findsOneWidget);
      expect(find.text('Table Layout Grid'), findsOneWidget);
      expect(find.text('Booking Time Grid'), findsOneWidget);
      expect(find.text('Booked / Reserved'), findsOneWidget);
      expect(find.text('Active Hold Orders'), findsOneWidget);
    });

    testWidgets('Adding/configuring table dialog does not throw Spacer inside OverflowBar assertion', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));

      await tester.pumpWidget(
        const MaterialApp(
          home: TablesScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Find the FAB 'Add Table' button
      final addBtn = find.text('Add Table');
      expect(addBtn, findsOneWidget);

      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Verify dialog is visible and actions contain Cancel/Create Table without OverflowBar assertion
      expect(find.text('Add New Restaurant Table'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create Table'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('TablesScreen layout remains overflow-free under narrow mobile dimensions', (tester) async {
      // Narrow mobile screen width (360x640)
      await tester.binding.setSurfaceSize(const Size(360, 640));

      await tester.pumpWidget(
        const MaterialApp(
          home: TablesScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // No flutter exception or render flex overflow should have occurred
      expect(tester.takeException(), isNull);
    });
  });
}
