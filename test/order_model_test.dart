import 'package:flutter_test/flutter_test.dart';
import 'package:dine_master/models/order_model.dart';

void main() {
  group('OrderItemModel Unit Tests', () {
    test('OrderItemModel fromMap parses correctly', () {
      final map = {
        'id': 1,
        'order_id': 10,
        'product_id': 3,
        'quantity': 2,
        'price': '240.5',
        'notes': 'No onions',
        'status': 'Cooking',
        'kot_id': 7,
      };

      final item = OrderItemModel.fromMap(map);

      expect(item.id, 1);
      expect(item.orderId, 10);
      expect(item.productId, 3);
      expect(item.quantity, 2);
      expect(item.price, 240.5);
      expect(item.notes, 'No onions');
      expect(item.status, 'Cooking');
      expect(item.kotId, 7);
    });

    test('OrderItemModel fromMap applies defaults when fields are missing', () {
      final item = OrderItemModel.fromMap({'product_id': 5});

      expect(item.quantity, 1);
      expect(item.price, 0.0);
      expect(item.status, 'Pending');
      expect(item.notes, isNull);
      expect(item.kotId, isNull);
    });

    test('OrderItemModel toMap converts correctly', () {
      final item = OrderItemModel(
        id: 2,
        orderId: 11,
        productId: 8,
        quantity: 3,
        price: 150.0,
        notes: 'Extra spicy',
        status: 'Ready',
        kotId: 4,
      );

      final map = item.toMap();

      expect(map['id'], 2);
      expect(map['order_id'], 11);
      expect(map['product_id'], 8);
      expect(map['quantity'], 3);
      expect(map['price'], 150.0);
      expect(map['notes'], 'Extra spicy');
      expect(map['status'], 'Ready');
      expect(map['kot_id'], 4);
    });

    test('OrderItemModel toMap omits null optional keys', () {
      final item = OrderItemModel(productId: 9, quantity: 1, price: 80.0);
      final map = item.toMap();

      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('order_id'), isFalse);
      expect(map['notes'], isNull);
      expect(map.containsKey('kot_id'), isFalse);
    });

    test('OrderItemModel copyWith updates fields correctly', () {
      final item = OrderItemModel(productId: 1, quantity: 1, price: 100.0, status: 'Pending');
      final updated = item.copyWith(quantity: 4, status: 'Served', notes: 'Less oil');

      expect(updated.productId, 1);
      expect(updated.quantity, 4);
      expect(updated.price, 100.0);
      expect(updated.status, 'Served');
      expect(updated.notes, 'Less oil');
      expect(updated.id, isNull);
    });
  });

  group('OrderModel Unit Tests', () {
    test('OrderModel fromMap parses all tracking fields', () {
      final map = {
        'id': 101,
        'table_id': 4,
        'customer_id': 2,
        'waiter_id': 9,
        'total_amount': '1240.75',
        'status': 'Preparing',
        'type': 'Dine-in',
        'order_time': '2026-01-05T12:30:00.000',
        'notes': 'Anniversary setup',
        'restaurant_id': 1,
        'payment_status': 'Paid',
        'payment_method': 'UPI',
        'discount_amount': '80.00',
        'customer_name': 'Amit Shah',
        'customer_phone': '9876543210',
        'order_taker_name': 'Rahul',
        'order_taker_id': 3,
        'delivered_by_name': 'Surendra',
        'delivered_by_id': 6,
        'delivery_timestamp': '2026-01-05T13:10:00.000',
        'guest_count': 6,
      };

      final order = OrderModel.fromMap(map);

      expect(order.id, 101);
      expect(order.tableId, 4);
      expect(order.customerId, 2);
      expect(order.waiterId, 9);
      expect(order.totalAmount, 1240.75);
      expect(order.status, 'Preparing');
      expect(order.type, 'Dine-in');
      expect(order.notes, 'Anniversary setup');
      expect(order.restaurantId, 1);
      expect(order.paymentStatus, 'Paid');
      expect(order.paymentMethod, 'UPI');
      expect(order.discountAmount, 80.0);
      expect(order.customerName, 'Amit Shah');
      expect(order.customerPhone, '9876543210');
      expect(order.orderTakerName, 'Rahul');
      expect(order.orderTakerId, 3);
      expect(order.deliveredByName, 'Surendra');
      expect(order.deliveredById, 6);
      expect(order.deliveryTimestamp, '2026-01-05T13:10:00.000');
      expect(order.guestCount, 6);
    });

    test('OrderModel fromMap applies defaults for empty order maps', () {
      final order = OrderModel.fromMap({});

      expect(order.totalAmount, 0.0);
      expect(order.status, 'Received');
      expect(order.type, 'Dine-in');
      expect(order.paymentStatus, 'Unpaid');
      expect(order.discountAmount, 0.0);
      expect(order.orderTime, isNotNull);
    });

    test('OrderModel toMap converts all fields', () {
      final order = OrderModel(
        id: 7,
        tableId: 2,
        waiterId: 5,
        totalAmount: 500.0,
        status: 'Completed',
        type: 'Parcel',
        orderTime: '2026-02-01T09:00:00.000',
        notes: 'Double parcel',
        restaurantId: 1,
        paymentStatus: 'Paid',
        paymentMethod: 'Cash',
        discountAmount: 25.0,
        customerName: 'Neha',
        guestCount: 2,
      );

      final map = order.toMap();

      expect(map['id'], 7);
      expect(map['table_id'], 2);
      expect(map['total_amount'], 500.0);
      expect(map['status'], 'Completed');
      expect(map['type'], 'Parcel');
      expect(map['order_time'], '2026-02-01T09:00:00.000');
      expect(map['notes'], 'Double parcel');
      expect(map['restaurant_id'], 1);
      expect(map['payment_status'], 'Paid');
      expect(map['payment_method'], 'Cash');
      expect(map['discount_amount'], 25.0);
      expect(map['customer_name'], 'Neha');
      expect(map['guest_count'], 2);
      expect(map.containsKey('customer_id'), isFalse);
      expect(map['delivered_by_id'], isNull);
      expect(map['delivered_by_name'], isNull);
    });

    test('OrderModel copyWith preserves unmodified fields', () {
      final order = OrderModel(
        id: 1,
        totalAmount: 900.0,
        status: 'Received',
        type: 'Delivery',
        orderTime: '2026-03-01T08:00:00.000',
        customerName: 'Ravi',
      );

      final updated = order.copyWith(status: 'Served');

      expect(updated.id, 1);
      expect(updated.totalAmount, 900.0);
      expect(updated.type, 'Delivery');
      expect(updated.orderTime, '2026-03-01T08:00:00.000');
      expect(updated.customerName, 'Ravi');
      expect(updated.status, 'Served');
    });
  });
}