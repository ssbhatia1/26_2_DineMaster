import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';
import '../waiter_models.dart';

class WaiterFloorPlanView extends StatelessWidget {
  final List<WaiterTableInfo> tableInfoList;
  final List<String> sectionsList;
  final String selectedSectionFilter;
  final String selectedStatusFilter;
  final Function(String) onSectionFilterChanged;
  final Function(String) onStatusFilterChanged;
  final Function(WaiterTableInfo) onTableCardTap;

  const WaiterFloorPlanView({
    super.key,
    required this.tableInfoList,
    required this.sectionsList,
    required this.selectedSectionFilter,
    required this.selectedStatusFilter,
    required this.onSectionFilterChanged,
    required this.onStatusFilterChanged,
    required this.onTableCardTap,
  });

  // --- STATUS COLOR HELPERS ---
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Available':
        return const Color(0xFF2E7D32); // Emerald Green
      case 'Occupied':
        return const Color(0xFF1565C0); // Vibrant Blue
      case 'Reserved':
        return const Color(0xFFE65100); // Amber Orange
      case 'Ordering':
        return const Color(0xFF3949AB); // Indigo
      case 'Preparing':
      case 'Sent to Kitchen':
        return const Color(0xFFF57C00); // Bright Orange
      case 'Ready':
        return Colors.purple;
      case 'Served':
        return const Color(0xFF00897B); // Teal
      case 'Billing Pending':
      case 'Bill Requested':
        return const Color(0xFFF9A825); // Gold / Yellow
      case 'Cleaning':
        return const Color(0xFF0288D1); // Cyan Blue
      case 'Out of Service':
        return const Color(0xFF546E7A); // Slate Grey
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getTableTypeIcon(String tableType) {
    switch (tableType) {
      case 'Booth':
        return Icons.weekend_outlined;
      case 'Round Table':
        return Icons.circle_outlined;
      case 'Counter':
      case 'Bar Counter':
        return Icons.wine_bar;
      case 'Outdoor Table':
        return Icons.deck_outlined;
      default:
        return Icons.table_restaurant;
    }
  }

  Widget _buildLegendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Collapse merged members into their primary/anchor table card so the
    // whole merged group appears as a single entity for order taking.
    final filteredTables = tableInfoList
        .where((ti) => ti.table.mergedWithId == null)
        .where((ti) {
          final matchesSection = selectedSectionFilter == 'All' || ti.table.section == selectedSectionFilter;
          final matchesStatus = selectedStatusFilter == 'All' || ti.effectiveStatus == selectedStatusFilter;
          return matchesSection && matchesStatus;
        })
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section & Status Filters
          Row(
            children: [
              // Section Filter Chips
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sectionsList.length,
                    itemBuilder: (context, index) {
                      final sec = sectionsList[index];
                      final isSelected = sec == selectedSectionFilter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(sec, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            onSectionFilterChanged(sec);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Status Filter Chips
              DropdownButton<String>(
                value: selectedStatusFilter,
                underline: const SizedBox(),
                items: ['All', 'Available', 'Occupied', 'Billing Pending', 'Served', 'Cleaning'].map((st) {
                  return DropdownMenuItem<String>(
                    value: st,
                    child: Text('Status: $st', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    onStatusFilterChanged(val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Floor Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendChip(const Color(0xFF2E7D32), 'Available'),
              _buildLegendChip(const Color(0xFF1565C0), 'Occupied'),
              _buildLegendChip(const Color(0xFFF9A825), 'Billing Pending'),
              _buildLegendChip(const Color(0xFF00897B), 'Served'),
              _buildLegendChip(const Color(0xFF0288D1), 'Cleaning'),
            ],
          ),
          const SizedBox(height: 16),

          // Tables Grid
          Expanded(
            child: filteredTables.isEmpty
                ? const Center(child: Text('No tables found for this filter.', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 280,
                      mainAxisExtent: 230,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: filteredTables.length,
                    itemBuilder: (context, index) {
                      final tableInfo = filteredTables[index];
                      final table = tableInfo.table;
                      final isMergedGroup = tableInfo.isMergedGroup;
                      final activeOrder = tableInfo.activeOrder;
                      final activeBooking = tableInfo.activeBooking;
                      final effectiveStatus = tableInfo.effectiveStatus;
                      final statusColor = _getStatusColor(effectiveStatus);
                      final typeIcon = _getTableTypeIcon(table.tableType);

                      // Combined capacity of the whole merged group
                      final combinedCapacity = tableInfo.combinedCapacity;

                      String capacityText = '$combinedCapacity Seats';
                      if (activeOrder != null && activeOrder['guest_count'] != null) {
                        capacityText = '${activeOrder['guest_count']} / $combinedCapacity Seats';
                      }

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: statusColor.withAlpha(90), width: 1.2),
                        ),
                        color: Colors.white,
                        surfaceTintColor: Colors.transparent,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onTableCardTap(tableInfo),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Header Bar
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                color: statusColor.withAlpha(30),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 13,
                                            backgroundColor: statusColor,
                                            child: Icon(typeIcon, color: Colors.white, size: 14),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            table.tableNumber,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: statusColor),
                                          ),
                                          if (table.name != null && table.name!.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '(${table.name})',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                          if (isMergedGroup) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withAlpha(40),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('MERGED', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.blue)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        effectiveStatus.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Table Attributes
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade700),
                                          const SizedBox(width: 3),
                                          Text(table.section, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.people_outline, size: 12, color: Colors.grey.shade700),
                                          const SizedBox(width: 3),
                                          Text(capacityText, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    if (activeBooking != null) ...[
                                      const Spacer(),
                                      const Icon(Icons.bookmark, size: 16, color: Colors.amber),
                                    ],
                                  ],
                                ),
                              ),

                              // Reservation Highlight if active
                              if (activeBooking != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Text(
                                      'Reserved: ${activeBooking['customer_name'] ?? 'Guest'} (${activeBooking['guest_count'] ?? table.capacity} guests)',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],

                              const Spacer(),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12.0),
                                child: Divider(height: 1),
                              ),

                              // Active Order Highlights or Idle State
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                                child: activeOrder != null
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Order #${activeOrder['id']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                                              Text('${tableInfo.orderItemsCount} items', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                                            ],
                                          ),
                                          Text(
                                            '₹${activeOrder['total_amount']}',
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                                          ),
                                        ],
                                      )
                                    : Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                                          child: Text(
                                            'No Active Orders',
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
