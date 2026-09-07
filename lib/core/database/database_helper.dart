import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'network_database.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static int? currentRestaurantId = 1; // Default to 1

  DatabaseHelper._init();

  Future<Database> get database async {
    final prefs = await SharedPreferences.getInstance();
    final isServer = prefs.getBool('is_server') ?? true;
    
    if (!isServer) {
      final serverIp = prefs.getString('server_ip') ?? 'localhost';
      return NetworkDatabase(serverIp: serverIp);
    }

    if (_database != null) return _database!;
    _database = await _initDB('dinemaster_restaurant.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final oldPath = join(dbPath, 'nexodine_restaurant.db');
    final path = join(dbPath, filePath);
    if (await File(oldPath).exists() && !await File(path).exists()) {
      try {
        await File(oldPath).copy(path);
      } catch (_) {}
    }

    final db = await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
    await _ensureTablesExist(db);
    return db;
  }

  Future<void> _ensureTablesExist(Database db) async {
    // 1. Check/create ingredients
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        stock_quantity REAL NOT NULL DEFAULT 0,
        restaurant_id INTEGER,
        FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
      )
    ''');

    // 2. Check/create recipes
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        ingredient_id INTEGER,
        quantity_used REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id),
        FOREIGN KEY (ingredient_id) REFERENCES inventory (id)
      )
    ''');

    // 3. Check/create suppliers
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        contact TEXT,
        address TEXT,
        restaurant_id INTEGER,
        FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
      )
    ''');

    // 4. Alter products to add recipe and preference columns if missing
    final columns = {
      'recipe_steps': 'TEXT',
      'prep_time': 'INTEGER',
      'cook_time': 'INTEGER',
      'servings': 'INTEGER',
      'difficulty': 'TEXT',
      'video_path': 'TEXT',
      'gst_percentage': 'REAL DEFAULT 5.0',
      'dietary_preferences': 'TEXT',
      'taste_preferences': 'TEXT',
      'attributes': 'TEXT',
      'custom_dietary_notes': 'TEXT',
    };

    for (var entry in columns.entries) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {
        // Column already exists
      }
    }

    // Alter tables to add table configuration columns if missing
    final tableColumns = {
      'name': 'TEXT',
      'section': 'TEXT DEFAULT \'Main Hall\'',
      'table_type': 'TEXT DEFAULT \'Standard Table\'',
      'is_active': 'INTEGER DEFAULT 1',
      'is_reservable': 'INTEGER DEFAULT 1',
      'notes': 'TEXT',
      'merged_with_id': 'INTEGER',
    };
    for (var entry in tableColumns.entries) {
      try {
        await db.execute('ALTER TABLE tables ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {}
    }

    // Alter orders to add columns if missing
    final orderColumns = {
      'customer_name': 'TEXT',
      'customer_phone': 'TEXT',
      'payment_status': 'TEXT DEFAULT \'Unpaid\'',
      'payment_method': 'TEXT',
      'discount_amount': 'REAL DEFAULT 0',
      'order_taker_name': 'TEXT',
      'order_taker_id': 'INTEGER',
      'delivered_by_name': 'TEXT',
      'delivered_by_id': 'INTEGER',
      'delivery_timestamp': 'TEXT',
      'guest_count': 'INTEGER',
    };
    for (var entry in orderColumns.entries) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {}
    }

    // Alter bookings to add columns if missing
    final bookingColumns = {
      'customer_name': 'TEXT',
      'customer_phone': 'TEXT',
      'guest_count': 'INTEGER',
    };
    for (var entry in bookingColumns.entries) {
      try {
        await db.execute('ALTER TABLE bookings ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {}
    }

    // Alter order_items to add kot_id column if missing
    try {
      await db.execute('ALTER TABLE order_items ADD COLUMN kot_id INTEGER');
    } catch (_) {}

    // Alter expenses to add restaurant_id column if missing
    try {
      await db.execute('ALTER TABLE expenses ADD COLUMN restaurant_id INTEGER');
    } catch (_) {}

    // Alter users table to add contact details and shift timing if missing
    final userColumns = {
      'contact_details': 'TEXT',
      'shift_timing': 'TEXT',
    };
    for (var entry in userColumns.entries) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {}
    }

    // Create order_status_logs table if missing
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_status_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        changed_at TEXT NOT NULL,
        changed_by TEXT,
        notes TEXT
      )
    ''');

    // Alter kot table to add cooking/estimation columns
    final kotColumns = {
      'started_cooking_at': 'TEXT',
      'ready_at': 'TEXT',
      'served_at': 'TEXT',
      'delay_reason': 'TEXT',
      'chef_name': 'TEXT',
      'priority': 'TEXT DEFAULT \'Normal\'',
      'estimated_time': 'INTEGER DEFAULT 15',
    };
    for (var entry in kotColumns.entries) {
      try {
        await db.execute('ALTER TABLE kot ADD COLUMN ${entry.key} ${entry.value}');
      } catch (_) {}
    }

    // Create table_types and table_sections if missing
    await db.execute('''
      CREATE TABLE IF NOT EXISTS table_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        restaurant_id INTEGER
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS table_sections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        restaurant_id INTEGER
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE restaurants (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          address TEXT,
          phone TEXT,
          created_at TEXT
        )
      ''');
      
      await db.execute('ALTER TABLE tables ADD COLUMN restaurant_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN restaurant_id INTEGER');
      await db.execute('ALTER TABLE orders ADD COLUMN restaurant_id INTEGER');
      await db.execute('ALTER TABLE inventory ADD COLUMN restaurant_id INTEGER');
      
      // Insert a default restaurant so existing data can link to it
      final now = DateTime.now().toIso8601String();
      final restId = await db.insert('restaurants', {
        'name': 'Default Restaurant',
        'created_at': now,
      });
      
      // Update existing data to use default restaurant
      await db.update('tables', {'restaurant_id': restId});
      await db.update('products', {'restaurant_id': restId});
      await db.update('orders', {'restaurant_id': restId});
      await db.update('inventory', {'restaurant_id': restId});
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE bookings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_id INTEGER,
          customer_id INTEGER,
          booking_time TEXT NOT NULL,
          status TEXT NOT NULL, -- Pending, Confirmed, Cancelled
          notes TEXT,
          restaurant_id INTEGER,
          FOREIGN KEY (table_id) REFERENCES tables (id),
          FOREIGN KEY (customer_id) REFERENCES customers (id),
          FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('ALTER TABLE products ADD COLUMN ingredients TEXT');
      await db.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE,
          restaurant_id INTEGER,
          FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
        )
      ''');
      
      final defaultCategories = ['Starters', 'Main Course', 'Breads', 'Beverages', 'Desserts'];
      for (var cat in defaultCategories) {
        try {
          await db.insert('categories', {
            'name': cat,
            'restaurant_id': 1,
          });
        } catch (e) {
          // Ignore if already exists
        }
      }
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE ingredients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          unit TEXT NOT NULL,
          stock_quantity REAL NOT NULL DEFAULT 0,
          restaurant_id INTEGER,
          FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
        )
      ''');

      await db.execute('''
        CREATE TABLE recipes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER,
          ingredient_id INTEGER,
          quantity_used REAL NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id),
          FOREIGN KEY (ingredient_id) REFERENCES inventory (id)
        )
      ''');

      await db.execute('''
        CREATE TABLE suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          contact TEXT,
          address TEXT,
          restaurant_id INTEGER,
          FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
        )
      ''');
    }

    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_status TEXT DEFAULT \'Unpaid\'');
        await db.execute('ALTER TABLE orders ADD COLUMN payment_method TEXT');
      } catch (e) {
        // Column might already exist
      }
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN discount_amount REAL DEFAULT 0');
      } catch (e) {
        // Column might already exist
      }
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'INTEGER NOT NULL'; // 0 for false, 1 for true
    const intType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';
    const textNullable = 'TEXT';

    // Restaurants Table
    await db.execute('''
CREATE TABLE restaurants (
  id $idType,
  name $textType,
  address $textNullable,
  phone $textNullable,
  created_at $textType
)
''');

    // Users Table
    await db.execute('''
CREATE TABLE users (
  id $idType,
  name $textType,
  username $textType UNIQUE,
  password $textType,
  role $textType,
  is_active $boolType DEFAULT 1,
  contact_details TEXT,
  shift_timing TEXT,
  created_at $textType
)
''');

    // Customers Table
    await db.execute('''
CREATE TABLE customers (
  id $idType,
  name $textType,
  phone $textType UNIQUE,
  email $textNullable,
  loyalty_points $intType DEFAULT 0,
  created_at $textType
)
''');

    // Tables Table
    await db.execute('''
CREATE TABLE tables (
  id $idType,
  table_number $textType UNIQUE,
  name $textNullable,
  capacity $intType,
  status $textType, -- Available, Occupied, Reserved, Ordering, Preparing, Bill Requested, Payment Pending, Paid, Cleaning, Out of Service
  section TEXT DEFAULT 'Main Hall',
  table_type TEXT DEFAULT 'Standard Table',
  is_active INTEGER DEFAULT 1,
  is_reservable INTEGER DEFAULT 1,
  notes TEXT,
  merged_with_id INTEGER,
  waiter_id INTEGER,
  restaurant_id INTEGER,
  FOREIGN KEY (waiter_id) REFERENCES users (id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    // Products/Menu Items Table
    await db.execute('''
CREATE TABLE products (
  id $idType,
  name $textType,
  description $textNullable,
  ingredients $textNullable,
  price $realType,
  category $textType,
  is_veg $boolType,
  image_path $textNullable,
  is_available $boolType DEFAULT 1,
  gst_percentage REAL DEFAULT 5.0,
  dietary_preferences TEXT,
  taste_preferences TEXT,
  attributes TEXT,
  custom_dietary_notes TEXT,
  restaurant_id INTEGER,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    await db.execute('''
CREATE TABLE categories (
  id $idType,
  name $textType UNIQUE,
  restaurant_id INTEGER,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    await db.execute('''
CREATE TABLE table_types (
  id $idType,
  name $textType UNIQUE,
  restaurant_id INTEGER
)
''');

    await db.execute('''
CREATE TABLE table_sections (
  id $idType,
  name $textType UNIQUE,
  restaurant_id INTEGER
)
''');


    // Orders Table
    await db.execute('''
CREATE TABLE orders (
  id $idType,
  table_id INTEGER,
  customer_id INTEGER,
  waiter_id INTEGER,
  total_amount $realType,
  status $textType, -- Received, Preparing, Ready, Served, Completed
  type $textType, -- Dine-in, Parcel, Delivery
  order_time $textType,
  notes $textNullable,
  restaurant_id INTEGER,
  payment_status TEXT DEFAULT 'Unpaid',
  payment_method TEXT,
  discount_amount REAL DEFAULT 0,
  customer_name TEXT,
  customer_phone TEXT,
  order_taker_name TEXT,
  order_taker_id INTEGER,
  delivered_by_name TEXT,
  delivered_by_id INTEGER,
  delivery_timestamp TEXT,
  guest_count INTEGER,
  FOREIGN KEY (table_id) REFERENCES tables (id),
  FOREIGN KEY (customer_id) REFERENCES customers (id),
  FOREIGN KEY (waiter_id) REFERENCES users (id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    // Order Items Table
    await db.execute('''
CREATE TABLE order_items (
  id $idType,
  order_id INTEGER,
  product_id INTEGER,
  quantity $intType,
  price $realType,
  notes $textNullable,
  status $textType, -- Pending, Cooking, Ready, Served
  kot_id INTEGER,
  FOREIGN KEY (order_id) REFERENCES orders (id),
  FOREIGN KEY (product_id) REFERENCES products (id),
  FOREIGN KEY (kot_id) REFERENCES kot (id)
)
''');

    // KOT Table
    await db.execute('''
CREATE TABLE kot (
  id $idType,
  order_id INTEGER,
  kot_number $textType,
  status $textType, -- Pending, Cooking, Ready, Served
  created_at $textType,
  started_cooking_at $textNullable,
  ready_at $textNullable,
  served_at $textNullable,
  delay_reason $textNullable,
  chef_name $textNullable,
  priority $textNullable DEFAULT 'Normal',
  estimated_time $intType DEFAULT 15,
  FOREIGN KEY (order_id) REFERENCES orders (id)
)
''');

    // Order Status Logs Table
    await db.execute('''
CREATE TABLE order_status_logs (
  id $idType,
  order_id INTEGER,
  status $textType,
  changed_at $textType,
  changed_by $textNullable,
  notes $textNullable
)
''');

    // Payments Table
    await db.execute('''
CREATE TABLE payments (
  id $idType,
  order_id INTEGER,
  amount $realType,
  payment_mode $textType, -- Cash, UPI, Card, Wallet
  payment_time $textType,
  FOREIGN KEY (order_id) REFERENCES orders (id)
)
''');

    // Inventory Table
    await db.execute('''
CREATE TABLE inventory (
  id $idType,
  item_name $textType,
  current_stock $realType,
  unit $textType,
  low_stock_threshold $realType,
  expiry_date $textNullable,
  restaurant_id INTEGER,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    // Vendors Table
    await db.execute('''
CREATE TABLE vendors (
  id $idType,
  name $textType,
  contact_person $textNullable,
  phone $textType,
  email $textNullable,
  address $textNullable
)
''');

    // Expenses Table
    await db.execute('''
CREATE TABLE expenses (
  id $idType,
  description $textType,
  amount $realType,
  date $textType,
  category $textType,
  restaurant_id INTEGER,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    // Offers Table
    await db.execute('''
CREATE TABLE offers (
  id $idType,
  name $textType,
  code $textType UNIQUE,
  discount_percentage $realType,
  is_active $boolType DEFAULT 1
)
''');

    // Loyalty Transactions Table
    await db.execute('''
CREATE TABLE loyalty_transactions (
  id $idType,
  customer_id INTEGER,
  points $intType,
  transaction_type $textType, -- Earned, Redeemed
  date $textType,
  FOREIGN KEY (customer_id) REFERENCES customers (id)
)
''');

    // Bookings Table
    await db.execute('''
CREATE TABLE bookings (
  id $idType,
  table_id INTEGER,
  customer_id INTEGER,
  customer_name TEXT,
  customer_phone TEXT,
  guest_count INTEGER,
  booking_time $textType,
  status $textType, -- Pending, Confirmed, Cancelled
  notes $textNullable,
  restaurant_id INTEGER,
  FOREIGN KEY (table_id) REFERENCES tables (id),
  FOREIGN KEY (customer_id) REFERENCES customers (id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants (id)
)
''');

    // Insert Sample Data
    await _insertSampleData(db);
  }

  Future<void> _insertSampleData(Database db) async {
    final now = DateTime.now().toIso8601String();
    
    // Insert Default Restaurant
    final restId = await db.insert('restaurants', {
      'name': 'Default Restaurant',
      'created_at': now,
    });

    // Insert Users
    await db.insert('users', {
      'name': 'Owner User',
      'username': 'owner',
      'password': hashPassword('owner123'),
      'role': 'Owner',
      'is_active': 1,
      'created_at': now
    });
    
    await db.insert('users', {
      'name': 'Manager User',
      'username': 'manager',
      'password': hashPassword('manager123'),
      'role': 'Manager',
      'is_active': 1,
      'created_at': now
    });

    await db.insert('users', {
      'name': 'Cashier User',
      'username': 'cashier',
      'password': hashPassword('cashier123'),
      'role': 'Cashier',
      'is_active': 1,
      'created_at': now
    });

    // Seed default Waiters
    await db.insert('users', {
      'name': 'John Waiter',
      'username': 'john_waiter',
      'password': hashPassword('password123'),
      'role': 'Waiter',
      'contact_details': '+91 99999 88888',
      'shift_timing': 'Morning (09:00 AM - 05:00 PM)',
      'is_active': 1,
      'created_at': now
    });
    await db.insert('users', {
      'name': 'Sarah Waiter',
      'username': 'sarah_waiter',
      'password': hashPassword('password123'),
      'role': 'Waiter',
      'contact_details': '+91 99999 77777',
      'shift_timing': 'Evening (05:00 PM - 01:00 AM)',
      'is_active': 1,
      'created_at': now
    });

    // Seed default Chefs
    await db.insert('users', {
      'name': 'Chef Marco',
      'username': 'chef_marco',
      'password': hashPassword('password123'),
      'role': 'Chef',
      'contact_details': '+91 99999 66666',
      'shift_timing': 'Morning (09:00 AM - 05:00 PM)',
      'is_active': 1,
      'created_at': now
    });
    await db.insert('users', {
      'name': 'Chef Priya',
      'username': 'chef_priya',
      'password': hashPassword('password123'),
      'role': 'Chef',
      'contact_details': '+91 99999 55555',
      'shift_timing': 'Evening (05:00 PM - 01:00 AM)',
      'is_active': 1,
      'created_at': now
    });

    // Insert Sample Tables
    for (int i = 1; i <= 10; i++) {
      await db.insert('tables', {
        'table_number': 'T$i',
        'capacity': 4,
        'status': 'Available',
        'restaurant_id': restId
      });
    }

    // Insert Sample Products
    await db.insert('products', {
      'name': 'Paneer Butter Masala',
      'price': 250.0,
      'category': 'Main Course',
      'is_veg': 1,
      'restaurant_id': restId
    });
    await db.insert('products', {
      'name': 'Chicken Biryani',
      'price': 300.0,
      'category': 'Main Course',
      'is_veg': 0,
      'restaurant_id': restId
    });
    await db.insert('products', {
      'name': 'Garlic Naan',
      'price': 50.0,
      'category': 'Breads',
      'is_veg': 1,
      'restaurant_id': restId
    });
    await db.insert('products', {
      'name': 'Cold Coffee',
      'price': 120.0,
      'category': 'Beverages',
      'is_veg': 1,
      'restaurant_id': restId
    });

    // Insert Default Table Types
    final defaultTypes = ['Standard Table', 'Booth', 'Round Table', 'Square Table', 'Rectangle Table', 'Counter', 'Bar Counter', 'Outdoor Table'];
    for (var t in defaultTypes) {
      await db.insert('table_types', {'name': t, 'restaurant_id': restId});
    }

    // Insert Default Table Sections
    final defaultSections = ['Main Hall', 'AC Dining', 'Rooftop', 'Outdoor / Patio', 'VIP Lounge', 'Bar Counter'];
    for (var s in defaultSections) {
      await db.insert('table_sections', {'name': s, 'restaurant_id': restId});
    }
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> logOrderStatus(int orderId, String status, {String? changedBy, String? notes}) async {
    final db = await database;
    await db.insert('order_status_logs', {
      'order_id': orderId,
      'status': status,
      'changed_at': DateTime.now().toIso8601String(),
      'changed_by': changedBy ?? 'System',
      'notes': notes,
    });
  }

  Future<void> generateKOTForOrder(int orderId, [String? chefName]) async {
    final db = await database;
    
    // Check if there are any order items that do not have a KOT assigned
    final List<Map<String, dynamic>> pendingItems = await db.query(
      'order_items',
      where: 'order_id = ? AND (kot_id IS NULL OR kot_id = 0)',
      whereArgs: [orderId],
    );

    if (pendingItems.isEmpty) {
      return;
    }

    // Count existing KOTs for this order
    final List<Map<String, dynamic>> existingKots = await db.query(
      'kot',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    final int nextKotIndex = existingKots.length + 1;
    final String kotNumber = 'KOT-#$orderId-$nextKotIndex';

    // Calculate product prep time
    int maxProductTime = 10; // Default fallback
    for (var item in pendingItems) {
      final productId = item['product_id'];
      final List<Map<String, dynamic>> productMaps = await db.query(
        'products',
        columns: ['prep_time', 'cook_time'],
        where: 'id = ?',
        whereArgs: [productId],
      );
      if (productMaps.isNotEmpty) {
        final prep = productMaps.first['prep_time'] as int? ?? 5;
        final cook = productMaps.first['cook_time'] as int? ?? 10;
        final total = prep + cook;
        if (total > maxProductTime) {
          maxProductTime = total;
        }
      }
    }

    // Workload delay: active KOTs in progress
    final List<Map<String, dynamic>> activeKots = await db.query(
      'kot',
      where: 'status IN (\'Pending\', \'Cooking\')',
    );
    final workloadDelay = activeKots.length * 2;
    final estimatedTime = maxProductTime + workloadDelay;

    // Determine priority based on order type
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      columns: ['type'],
      where: 'id = ?',
      whereArgs: [orderId],
    );
    String priority = 'Normal';
    if (orderMaps.isNotEmpty && (orderMaps.first['type'] == 'Dine-in' || orderMaps.first['type'] == 'Table Order')) {
      priority = 'High';
    }

    // Insert new KOT record
    final kotId = await db.insert('kot', {
      'order_id': orderId,
      'kot_number': kotNumber,
      'status': 'Pending',
      'created_at': DateTime.now().toIso8601String(),
      'priority': priority,
      'estimated_time': estimatedTime,
      if (chefName != null) 'chef_name': chefName,
    });

    // Update those order items to point to this new KOT and set their status to Pending
    await db.update(
      'order_items',
      {
        'kot_id': kotId,
        'status': 'Pending',
      },
      where: 'order_id = ? AND (kot_id IS NULL OR kot_id = 0)',
      whereArgs: [orderId],
    );

    // Log the order status change
    await logOrderStatus(orderId, 'Sent to Kitchen', notes: 'Generated KOT: $kotNumber with Est. Prep Time of $estimatedTime mins.');
  }

  Future<String> backupDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'dinemaster_restaurant.db');
    var dbFile = File(path);
    if (!await dbFile.exists()) {
      final legacyFile = File(join(dbPath, 'nexodine_restaurant.db'));
      if (await legacyFile.exists()) {
        dbFile = legacyFile;
      }
    }
    if (await dbFile.exists()) {
      final String homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      final backupDir = Directory(join(homeDir, 'Downloads', 'DineMasterBackups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final backupPath = join(backupDir.path, 'backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.db');
      await dbFile.copy(backupPath);
      return backupPath;
    }
    throw Exception('Database file not found');
  }

  Future<void> restoreDatabase(String backupPath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'dinemaster_restaurant.db');
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      final db = await database;
      await db.close();
      _database = null;
      await backupFile.copy(path);
      await database;
    } else {
      throw Exception('Backup file not found');
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
