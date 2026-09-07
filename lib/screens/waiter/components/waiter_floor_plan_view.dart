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
          final matchesStatus = selectedStatusFilter == 'All' || ti.table.status == selectedStatusFilter;
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
                      maxCrossAxisExtent: 240,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: filteredTables.length,
                    itemBuilder: (context, index) {
                      final tableInfo = filteredTables[index];
                      final table = tableInfo.table;
                      final isMergedGroup = tableInfo.isMergedGroup;
                      final activeOrder = tableInfo.activeOrder;
                      final statusColor = _getStatusColor(table.status);
                      final typeIcon = _getTableTypeIcon(table.tableType);

                      // Combined capacity of the whole merged group
                      final combinedCapacity = tableInfo.combinedCapacity;

                      String capacityText = 'Capacity: $combinedCapacity';
                      if (activeOrder != null && activeOrder['guest_count'] != null) {
                        capacityText = 'Guests: ${activeOrder['guest_count']} / Max: $combinedCapacity';
                      }

                      final titleText = isMergedGroup ? tableInfo.mergedTableNumbers : table.displayName;

                      return Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1.5),
                        ),
                        color: statusColor.withValues(alpha: 0.03),
                        child: InkWell(
                          onTap: () => onTableCardTap(tableInfo),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Table Type Icon & Status Badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: statusColor.withValues(alpha: 0.15),
                                          child: Icon(typeIcon, color: statusColor, size: 16),
                                        ),
                                        if (isMergedGroup) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.merge_type, size: 11, color: Colors.blue),
                                                SizedBox(width: 2),
                                                Text('MERGED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        table.status.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),

                                // Table Info
                                Text(
                                  titleText,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text('$capacityText | ${table.section}', style: const TextStyle(fontSize: 12, color: Colors.black54)),

                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                
                                // Active Order Highlights
                                if (activeOrder != null) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Order #', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text('${activeOrder['id']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Items:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text('${tableInfo.orderItemsCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Total:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text('₹${activeOrder['total_amount']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                                    ],
                                  ),
                                ] else ...[
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Text('No Active Orders', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
