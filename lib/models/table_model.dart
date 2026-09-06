class TableModel {
  final int? id;
  final String tableNumber;
  final String? name; // Optional table name/alias, e.g. "Window Booth 1"
  final int capacity;
  final String status; 
  // Statuses: 'Available', 'Occupied', 'Reserved', 'Ordering', 'Preparing', 
  // 'Bill Requested', 'Payment Pending', 'Paid', 'Cleaning', 'Out of Service'
  final String section; // e.g. 'Main Hall', 'AC Dining', 'Rooftop', 'Outdoor / Patio', 'VIP Lounge', 'Bar Counter'
  final String tableType; // e.g. 'Standard Table', 'Round Table', 'Square Table', 'Rectangle Table', 'Booth', 'Counter', 'Outdoor Table'
  final bool isActive;
  final bool isReservable;
  final String? notes;
  final int? waiterId;
  final String? waiterName; // Cached/joined from users table
  final int? restaurantId;
  final int? mergedWithId;

  TableModel({
    this.id,
    required this.tableNumber,
    this.name,
    required this.capacity,
    required this.status,
    this.section = 'Main Hall',
    this.tableType = 'Standard Table',
    this.isActive = true,
    this.isReservable = true,
    this.notes,
    this.waiterId,
    this.waiterName,
    this.restaurantId,
    this.mergedWithId,
  });

  // Helper getters for UI status checks
  bool get isAvailable => status == 'Available';
  bool get isOccupied => status == 'Occupied';
  bool get isReserved => status == 'Reserved';
  bool get isOrdering => status == 'Ordering';
  bool get isPreparing => status == 'Preparing';
  bool get isBillRequested => status == 'Bill Requested';
  bool get isPaymentPending => status == 'Payment Pending';
  bool get isPaid => status == 'Paid';
  bool get isCleaning => status == 'Cleaning';
  bool get isOutOfService => status == 'Out of Service';

  String get displayName => (name != null && name!.trim().isNotEmpty)
      ? '$tableNumber ($name)'
      : 'Table $tableNumber';

  TableModel copyWith({
    int? id,
    String? tableNumber,
    String? name,
    int? capacity,
    String? status,
    String? section,
    String? tableType,
    bool? isActive,
    bool? isReservable,
    String? notes,
    int? waiterId,
    String? waiterName,
    int? restaurantId,
    int? mergedWithId,
  }) {
    return TableModel(
      id: id ?? this.id,
      tableNumber: tableNumber ?? this.tableNumber,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      section: section ?? this.section,
      tableType: tableType ?? this.tableType,
      isActive: isActive ?? this.isActive,
      isReservable: isReservable ?? this.isReservable,
      notes: notes ?? this.notes,
      waiterId: waiterId ?? this.waiterId,
      waiterName: waiterName ?? this.waiterName,
      restaurantId: restaurantId ?? this.restaurantId,
      mergedWithId: mergedWithId ?? this.mergedWithId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_number': tableNumber,
      'name': name,
      'capacity': capacity,
      'status': status,
      'section': section,
      'table_type': tableType,
      'is_active': isActive ? 1 : 0,
      'is_reservable': isReservable ? 1 : 0,
      'notes': notes,
      'waiter_id': waiterId,
      'waiter_name': waiterName,
      'restaurant_id': restaurantId,
      'merged_with_id': mergedWithId,
    };
  }

  factory TableModel.fromMap(Map<String, dynamic> map) {
    return TableModel(
      id: map['id'],
      tableNumber: map['table_number'] ?? '',
      name: map['name'],
      capacity: map['capacity'] ?? 4,
      status: map['status'] ?? 'Available',
      section: map['section'] ?? 'Main Hall',
      tableType: map['table_type'] ?? 'Standard Table',
      isActive: map['is_active'] == null || map['is_active'] == 1 || map['is_active'] == true,
      isReservable: map['is_reservable'] == null || map['is_reservable'] == 1 || map['is_reservable'] == true,
      notes: map['notes'],
      waiterId: map['waiter_id'],
      waiterName: map['waiter_name'],
      restaurantId: map['restaurant_id'],
      mergedWithId: map['merged_with_id'],
    );
  }
}
