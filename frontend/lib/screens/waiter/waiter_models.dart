import '../../models/product_model.dart';
import '../../models/table_model.dart';

/// Representation of a customized cart item for the waiter
class WaiterCartItem {
  final ProductModel product;
  int quantity;
  String? dietaryPreference;
  String? tastePreference;
  String? notes;

  WaiterCartItem({
    required this.product,
    this.quantity = 1,
    this.dietaryPreference,
    this.tastePreference,
    this.notes,
  });

  String get formattedNotes {
    final List<String> parts = [];
    if (dietaryPreference != null && dietaryPreference!.isNotEmpty) {
      parts.add('[$dietaryPreference]');
    }
    if (tastePreference != null && tastePreference!.isNotEmpty) {
      parts.add('[$tastePreference]');
    }
    if (notes != null && notes!.trim().isNotEmpty) {
      parts.add(notes!.trim());
    }
    return parts.join(' ');
  }

  double get subtotal => product.price * quantity;
}

/// Enriched table container for waiter floor plan
class WaiterTableInfo {
  final TableModel table;
  final Map<String, dynamic>? activeOrder;
  final Map<String, dynamic>? activeBooking;
  final int orderItemsCount;

  /// Tables currently merged into this table (members whose [TableModel.mergedWithId]
  /// points to this table's id). Populated after all tables are loaded.
  List<TableModel> mergedTables;

  WaiterTableInfo({
    required this.table,
    this.activeOrder,
    this.activeBooking,
    this.orderItemsCount = 0,
    List<TableModel>? mergedTables,
  }) : mergedTables = mergedTables ?? [];

  bool get hasActiveOrder => activeOrder != null;
  bool get hasActiveBooking => activeBooking != null;

  String get effectiveStatus {
    if (activeOrder != null || activeBooking != null) {
      return 'Occupied';
    }
    return table.status;
  }

  /// Whether this table is the anchor of a merged group (it has member tables).
  bool get isMergedGroup => mergedTables.isNotEmpty;

  /// Combined seating capacity of the whole merged group (anchor + members).
  int get combinedCapacity =>
      table.capacity + mergedTables.fold<int>(0, (sum, t) => sum + t.capacity);

  /// Display label for the whole merged group, e.g. "T-01 + T-03".
  String get mergedTableNumbers => [table, ...mergedTables].map((t) => t.tableNumber).join(' + ');

  /// Display name to use in order taking, shows the full merged group when merged.
  String get displayNameForOrder =>
      isMergedGroup ? mergedTableNumbers : table.displayName;
}
