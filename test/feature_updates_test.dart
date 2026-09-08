import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dine_master/screens/splash_screen.dart';
import 'package:dine_master/screens/tables_screen.dart';
import 'package:dine_master/models/table_model.dart';
import 'package:dine_master/core/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Feature 1: Splash Screen Logo Tests', () {
    testWidgets('SplashScreen contains the existing application logo image', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'setup_data_choice': 'keep'});

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );
      await tester.pump();

      // Find the logo image widget
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      final assetImage = imageWidget.image as AssetImage;
      expect(assetImage.assetName, equals('assets/images/logo.jpg'));

      // Verify branding text
      expect(find.text('DINE MASTER'), findsOneWidget);
      expect(find.text('Enterprise Restaurant POS & Management'), findsOneWidget);

      // Drain any pending timers from splash
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Feature 2: Installation Data Handling Tests', () {
    test('checkPreviousDataExists detects existing db files correctly', () async {
      final dbPath = await getDatabasesPath();
      final testDbFile = File(p.join(dbPath, 'dinemaster_restaurant.db'));

      // If db file doesn't exist, create temporary file
      final existedBefore = await testDbFile.exists();
      if (!existedBefore) {
        await testDbFile.writeAsString('test-db-data');
      }

      final hasData = await DatabaseHelper.instance.checkPreviousDataExists();
      expect(hasData, isTrue);

      if (!existedBefore) {
        await testDbFile.delete();
      }
    });

    test('continueWithoutPreviousData archives rather than deleting existing data', () async {
      await DatabaseHelper.instance.close();
      final dbPath = await getDatabasesPath();
      final testDbFile = File(p.join(dbPath, 'dinemaster_restaurant.db'));
      await testDbFile.writeAsString('important-customer-data');

      final archivedPath = await DatabaseHelper.instance.continueWithoutPreviousData();
      expect(archivedPath, isNotNull);
      expect(await File(archivedPath!).exists(), isTrue);

      // Verify original file was archived/renamed, not permanently destroyed
      final archivedContent = await File(archivedPath).readAsString();
      expect(archivedContent, equals('important-customer-data'));

      // Clean up test archive file
      await File(archivedPath).delete();
    });
  });

  group('Feature 3: Booking Time Grid Tests', () {
    testWidgets('TablesScreen loads and exposes Booking Time Grid tab', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const MaterialApp(
          home: TablesScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify TabBar includes Booking Time Grid tab
      final tabFinder = find.text('Booking Time Grid');
      expect(tabFinder, findsOneWidget);

      // Tap tab and pump frame
      await tester.tap(tabFinder);
      await tester.pump(const Duration(milliseconds: 500));

      // Advance clock past sqflite's 10-second lock timer
      await tester.pump(const Duration(seconds: 11));
    });

    test('TableModel status and display name work properly in grid', () {
      final table = TableModel(
        id: 101,
        tableNumber: 'T99',
        name: 'Window View',
        capacity: 4,
        status: 'Available',
        section: 'Main Hall',
      );

      expect(table.displayName, equals('T99 (Window View)'));
      expect(table.isAvailable, isTrue);
      expect(table.capacity, equals(4));
    });
  });
}
