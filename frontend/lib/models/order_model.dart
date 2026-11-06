class OrderItemModel {
  final int? id;
  final int? orderId;
  final int productId;
  final String? productName;
  final int quantity;
  final double price;
  final String? notes;
  final String status; // Pending, Cooking, Ready, Served
  final int? kotId;

  OrderItemModel({
    this.id,
    this.orderId,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.price,
    this.notes,
    this.status = 'Pending',
    this.kotId,
  });

  OrderItemModel copyWith({
    int? id,
    int? orderId,
    int? productId,
    String? productName,
    int? quantity,
    double? price,
    String? notes,
    String? status,
    int? kotId,
  }) {
    return OrderItemModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      kotId: kotId ?? this.kotId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      'product_id': productId,
      'quantity': quantity,
      'price': price,
      'notes': notes,
      'status': status,
      if (kotId != null) 'kot_id': kotId,
    };
  }

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    dynamic value(String snakeCase, String camelCase) =>
        map[snakeCase] ?? map[camelCase];
    int? asInt(dynamic input) =>
        input is num ? input.toInt() : int.tryParse('$input');
    double? asDouble(dynamic input) =>
        input is num ? input.toDouble() : double.tryParse('$input');

    return OrderItemModel(
      id: asInt(map['id']),
      orderId: asInt(value('order_id', 'orderId')),
      productId: asInt(value('product_id', 'productId')) ?? 0,
      quantity: asInt(map['quantity']) ?? 1,
      price: asDouble(map['price']) ?? 0.0,
      notes: map['notes']?.toString(),
      productName: map['product_name'] ?? map['productName'],
      status: map['status']?.toString() ?? 'Pending',
      kotId: asInt(value('kot_id', 'kotId')),
    );
  }
}

class OrderModel {
  final int? id;
  final int? tableId;
  final int? customerId;
  final int? waiterId;
  final double totalAmount;
  final String status; // Received, Preparing, Ready, Served, Completed
  final String type; // Dine-in, Parcel, Delivery
  final String orderTime;
  final String? notes;
  final int? restaurantId;
  final String paymentStatus; // Unpaid, Paid
  final String? paymentMethod;
  final double discountAmount;

  // Additional Tracking Fields
  final String? customerName;
  final String? customerPhone;
  final String? orderTakerName;
  final int? orderTakerId;
  final String? deliveredByName;
  final int? deliveredById;
  final String? deliveryTimestamp;
  final int? guestCount;

  // Relationship properties (Optional, usually loaded separately or via joins)
  final List<OrderItemModel>? items;

  OrderModel({
    this.id,
    this.tableId,
    this.customerId,
    this.waiterId,
    required this.totalAmount,
    this.status = 'Received',
    this.type = 'Dine-in',
    required this.orderTime,
    this.notes,
    this.restaurantId,
    this.paymentStatus = 'Unpaid',
    this.paymentMethod,
    this.discountAmount = 0.0,
    this.customerName,
    this.customerPhone,
    this.orderTakerName,
    this.orderTakerId,
    this.deliveredByName,
    this.deliveredById,
    this.deliveryTimestamp,
    this.guestCount,
    this.items,
  });

  OrderModel copyWith({
    int? id,
    int? tableId,
    int? customerId,
    int? waiterId,
    double? totalAmount,
    String? status,
    String? type,
    String? orderTime,
    String? notes,
    int? restaurantId,
    String? paymentStatus,
    String? paymentMethod,
    double? discountAmount,
    String? customerName,
    String? customerPhone,
    String? orderTakerName,
    int? orderTakerId,
    String? deliveredByName,
    int? deliveredById,
    String? deliveryTimestamp,
    int? guestCount,
    List<OrderItemModel>? items,
  }) {
    return OrderModel(
      id: id ?? this.id,
      tableId: tableId ?? this.tableId,
      customerId: customerId ?? this.customerId,
      waiterId: waiterId ?? this.waiterId,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      type: type ?? this.type,
      orderTime: orderTime ?? this.orderTime,
      notes: notes ?? this.notes,
      restaurantId: restaurantId ?? this.restaurantId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      discountAmount: discountAmount ?? this.discountAmount,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      orderTakerName: orderTakerName ?? this.orderTakerName,
      orderTakerId: orderTakerId ?? this.orderTakerId,
      deliveredByName: deliveredByName ?? this.deliveredByName,
      deliveredById: deliveredById ?? this.deliveredById,
      deliveryTimestamp: deliveryTimestamp ?? this.deliveryTimestamp,
      guestCount: guestCount ?? this.guestCount,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (tableId != null) 'table_id': tableId,
      if (customerId != null) 'customer_id': customerId,
      if (waiterId != null) 'waiter_id': waiterId,
      'total_amount': totalAmount,
      'status': status,
      'type': type,
      'order_time': orderTime,
      'notes': notes,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'discount_amount': discountAmount,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'order_taker_name': orderTakerName,
      'order_taker_id': orderTakerId,
      'delivered_by_name': deliveredByName,
      'delivered_by_id': deliveredById,
      'delivery_timestamp': deliveryTimestamp,
      'guest_count': guestCount,
    };
  }

  factory OrderModel.fromMap(
    Map<String, dynamic> map, {
    List<OrderItemModel>? items,
  }) {
    dynamic value(String snakeCase, String camelCase) =>
        map[snakeCase] ?? map[camelCase];

    return OrderModel(
      id: (map['id'] as num?)?.toInt(),
      tableId: (value('table_id', 'tableId') as num?)?.toInt(),
      customerId: (value('customer_id', 'customerId') as num?)?.toInt(),
      waiterId: (value('waiter_id', 'waiterId') as num?)?.toInt(),
      totalAmount: value('total_amount', 'totalAmount') != null
          ? double.parse(value('total_amount', 'totalAmount').toString())
          : 0.0,
      status: map['status']?.toString() ?? 'Received',
      type: map['type']?.toString() ?? 'Dine-in',
      orderTime:
          value('order_time', 'orderTime')?.toString() ??
          DateTime.now().toIso8601String(),
      notes: map['notes']?.toString(),
      restaurantId: (value('restaurant_id', 'restaurantId') as num?)?.toInt(),
      paymentStatus:
          value('payment_status', 'paymentStatus')?.toString() ?? 'Unpaid',
      paymentMethod: value('payment_method', 'paymentMethod')?.toString(),
      discountAmount: value('discount_amount', 'discountAmount') != null
          ? double.parse(value('discount_amount', 'discountAmount').toString())
          : 0.0,
      customerName: value('customer_name', 'customerName')?.toString(),
      customerPhone: value('customer_phone', 'customerPhone')?.toString(),
      orderTakerName:
          value('order_taker_name', 'orderTakerName')?.toString() ??
          map['orderTaker']?.toString(),
      orderTakerId: (value('order_taker_id', 'orderTakerId') as num?)?.toInt(),
      deliveredByName:
          value('delivered_by_name', 'deliveredByName')?.toString() ??
          map['deliveredBy']?.toString(),
      deliveredById: (value('delivered_by_id', 'deliveredById') as num?)
          ?.toInt(),
      deliveryTimestamp: value(
        'delivery_timestamp',
        'deliveryTimestamp',
      )?.toString(),
      guestCount: (value('guest_count', 'guestCount') as num?)?.toInt(),
      items: items,
    );
  }
}
