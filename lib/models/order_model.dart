class OrderItemModel {
  final int? id;
  final int? orderId;
  final int productId;
  final int quantity;
  final double price;
  final String? notes;
  final String status; // Pending, Cooking, Ready, Served
  final int? kotId;

  OrderItemModel({
    this.id,
    this.orderId,
    required this.productId,
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
    return OrderItemModel(
      id: map['id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      quantity: map['quantity'] ?? 1,
      price: map['price'] != null ? double.parse(map['price'].toString()) : 0.0,
      notes: map['notes'],
      status: map['status'] ?? 'Pending',
      kotId: map['kot_id'],
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

  factory OrderModel.fromMap(Map<String, dynamic> map, {List<OrderItemModel>? items}) {
    return OrderModel(
      id: map['id'],
      tableId: map['table_id'],
      customerId: map['customer_id'],
      waiterId: map['waiter_id'],
      totalAmount: map['total_amount'] != null ? double.parse(map['total_amount'].toString()) : 0.0,
      status: map['status'] ?? 'Received',
      type: map['type'] ?? 'Dine-in',
      orderTime: map['order_time'] ?? DateTime.now().toIso8601String(),
      notes: map['notes'],
      restaurantId: map['restaurant_id'],
      paymentStatus: map['payment_status'] ?? 'Unpaid',
      paymentMethod: map['payment_method'],
      discountAmount: map['discount_amount'] != null ? double.parse(map['discount_amount'].toString()) : 0.0,
      customerName: map['customer_name'],
      customerPhone: map['customer_phone'],
      orderTakerName: map['order_taker_name'],
      orderTakerId: map['order_taker_id'],
      deliveredByName: map['delivered_by_name'],
      deliveredById: map['delivered_by_id'],
      deliveryTimestamp: map['delivery_timestamp'],
      guestCount: map['guest_count'],
      items: items,
    );
  }
}
