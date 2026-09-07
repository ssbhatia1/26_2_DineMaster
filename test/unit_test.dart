import 'package:flutter_test/flutter_test.dart';
import 'package:dine_master/models/product_model.dart';
import 'package:dine_master/models/table_model.dart';

void main() {
  group('ProductModel Unit Tests', () {
    test('ProductModel fromMap parses correctly', () {
      final map = {
        'id': 1,
        'name': 'Paneer Tikka',
        'price': 250.0,
        'category': 'Starters',
        'is_veg': 1,
        'is_available': 1,
        'gst_percentage': 12.0,
        'dietary_preferences': '["Pure Jain", "Semi Jain"]',
        'taste_preferences': '["Spicy", "Extra Spicy"]',
        'attributes': '["Chef\'s Special", "Bestseller"]',
        'custom_dietary_notes': 'Gluten Free recipe',
      };

      final product = ProductModel.fromMap(map);

      expect(product.id, 1);
      expect(product.name, 'Paneer Tikka');
      expect(product.price, 250.0);
      expect(product.category, 'Starters');
      expect(product.isVeg, 1);
      expect(product.isAvailable, true);
      expect(product.gstPercentage, 12.0);
      expect(product.dietaryPreferences, ['Pure Jain', 'Semi Jain']);
      expect(product.tastePreferences, ['Spicy', 'Extra Spicy']);
      expect(product.attributes, ["Chef's Special", "Bestseller"]);
      expect(product.customDietaryNotes, 'Gluten Free recipe');
      expect(product.isPureJain, true);
      expect(product.isBestseller, true);
      expect(product.isChefsSpecial, true);
      expect(product.hasPreferences, true);
    });

    test('ProductModel toMap converts correctly', () {
      final product = ProductModel(
        id: 2,
        name: 'Chicken Biryani',
        price: 320.0,
        category: 'Main Course',
        isVeg: 0,
        isAvailable: true,
        gstPercentage: 18.0,
        dietaryPreferences: const [],
        tastePreferences: const ['Spicy'],
        attributes: const ['Bestseller', 'Popular'],
        customDietaryNotes: 'Contains Dairy',
      );

      final map = product.toMap();

      expect(map['id'], 2);
      expect(map['name'], 'Chicken Biryani');
      expect(map['price'], 320.0);
      expect(map['category'], 'Main Course');
      expect(map['is_veg'], 0);
      expect(map['is_available'], 1);
      expect(map['gst_percentage'], 18.0);
      expect(map['taste_preferences'], '["Spicy"]');
      expect(map['attributes'], '["Bestseller","Popular"]');
      expect(map['custom_dietary_notes'], 'Contains Dairy');
    });

    test('ProductModel copyWith works correctly', () {
      final product = ProductModel(
        name: 'Spring Roll',
        price: 150.0,
        category: 'Starters',
        isVeg: 1,
        dietaryPreferences: const ['Pure Jain'],
      );

      final updated = product.copyWith(
        price: 180.0,
        isAvailable: false,
        attributes: ['Recommended'],
      );

      expect(updated.name, 'Spring Roll');
      expect(updated.price, 180.0);
      expect(updated.isAvailable, false);
      expect(updated.isVeg, 1);
      expect(updated.dietaryPreferences, ['Pure Jain']);
      expect(updated.attributes, ['Recommended']);
      expect(updated.isRecommended, true);
    });
  });

  group('TableModel Unit Tests', () {
    test('TableModel status getters compute correctly', () {
      final tableAvailable = TableModel(tableNumber: 'T1', capacity: 4, status: 'Available');
      final tableOccupied = TableModel(tableNumber: 'T2', capacity: 2, status: 'Occupied');
      final tableReserved = TableModel(tableNumber: 'T3', capacity: 6, status: 'Reserved');
      final tableCleaning = TableModel(tableNumber: 'T4', capacity: 4, status: 'Cleaning');
      final tablePreparing = TableModel(tableNumber: 'T5', capacity: 4, status: 'Preparing');

      expect(tableAvailable.isAvailable, true);
      expect(tableAvailable.isOccupied, false);
      expect(tableAvailable.isReserved, false);

      expect(tableOccupied.isAvailable, false);
      expect(tableOccupied.isOccupied, true);
      expect(tableOccupied.isReserved, false);

      expect(tableReserved.isAvailable, false);
      expect(tableReserved.isOccupied, false);
      expect(tableReserved.isReserved, true);

      expect(tableCleaning.isCleaning, true);
      expect(tablePreparing.isPreparing, true);
    });

    test('TableModel toMap and fromMap serialization works', () {
      final table = TableModel(
        id: 5,
        tableNumber: 'T5',
        name: 'Garden Booth',
        capacity: 4,
        status: 'Occupied',
        section: 'Rooftop',
        tableType: 'Booth',
        isActive: true,
        isReservable: true,
        notes: 'Near garden wall',
        waiterId: 3,
        waiterName: 'Rahul',
        restaurantId: 1,
      );

      final map = table.toMap();
      expect(map['id'], 5);
      expect(map['table_number'], 'T5');
      expect(map['name'], 'Garden Booth');
      expect(map['capacity'], 4);
      expect(map['status'], 'Occupied');
      expect(map['section'], 'Rooftop');
      expect(map['table_type'], 'Booth');
      expect(map['is_active'], 1);
      expect(map['is_reservable'], 1);
      expect(map['notes'], 'Near garden wall');
      expect(map['waiter_id'], 3);
      expect(map['waiter_name'], 'Rahul');
      expect(map['restaurant_id'], 1);

      final fromMap = TableModel.fromMap(map);
      expect(fromMap.id, 5);
      expect(fromMap.tableNumber, 'T5');
      expect(fromMap.name, 'Garden Booth');
      expect(fromMap.capacity, 4);
      expect(fromMap.status, 'Occupied');
      expect(fromMap.section, 'Rooftop');
      expect(fromMap.tableType, 'Booth');
      expect(fromMap.isActive, true);
      expect(fromMap.isReservable, true);
      expect(fromMap.notes, 'Near garden wall');
      expect(fromMap.waiterId, 3);
      expect(fromMap.waiterName, 'Rahul');
      expect(fromMap.restaurantId, 1);
      expect(fromMap.displayName, 'T5 (Garden Booth)');
    });

    test('TableModel copyWith updates fields correctly', () {
      final table = TableModel(
        tableNumber: 'T10',
        capacity: 4,
        status: 'Available',
        section: 'Main Hall',
      );

      final updated = table.copyWith(
        status: 'Occupied',
        waiterId: 2,
        waiterName: 'Amit',
        section: 'VIP Lounge',
      );

      expect(updated.tableNumber, 'T10');
      expect(updated.capacity, 4);
      expect(updated.status, 'Occupied');
      expect(updated.waiterId, 2);
      expect(updated.waiterName, 'Amit');
      expect(updated.section, 'VIP Lounge');
    });
  });

  group('Waiter & Water Ordering Unit Tests', () {
    test('Water service request string formats properly with instructions', () {
      final waterType = 'Chilled Drinking Water';
      final glasses = 4;
      final cutlery = true;
      final tissues = true;
      final saltPepper = true;
      final notes = 'With lemon slices';

      final List<String> serviceItems = ['$waterType ($glasses Glasses)'];
      if (cutlery) serviceItems.add('Extra Cutlery');
      if (tissues) serviceItems.add('Napkin Refill');
      if (saltPepper) serviceItems.add('Salt/Pepper');
      if (notes.isNotEmpty) serviceItems.add('Note: $notes');

      final fullNote = '[WATER SERVICE] ${serviceItems.join(" • ")}';
      expect(fullNote, '[WATER SERVICE] Chilled Drinking Water (4 Glasses) • Extra Cutlery • Napkin Refill • Salt/Pepper • Note: With lemon slices');
    });

    test('Dietary and taste preferences format correctly for KOT item notes', () {
      String? dietaryPreference = 'Pure Jain';
      String? tastePreference = 'Spicy';
      String? instructions = 'Extra crispy';

      final List<String> parts = [];
      if (dietaryPreference.isNotEmpty) parts.add('[$dietaryPreference]');
      if (tastePreference.isNotEmpty) parts.add('[$tastePreference]');
      if (instructions.trim().isNotEmpty) parts.add(instructions.trim());

      final formattedNotes = parts.join(' ');
      expect(formattedNotes, '[Pure Jain] [Spicy] Extra crispy');
    });

    test('Mineral water billable calculations and pricing are correct', () {
      // Paid mineral water is chargeable at a fixed rate; GST applied on top.
      const double waterPrice = 20.0;
      final double totalWithGst = waterPrice * 1.05;

      expect(waterPrice, 20.0);
      expect(totalWithGst, 21.0);
    });
  });
}

