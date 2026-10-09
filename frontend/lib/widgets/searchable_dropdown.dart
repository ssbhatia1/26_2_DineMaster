import 'package:flutter/material.dart';
import 'package:dine_master/core/theme/app_colors.dart';

class SearchableDropdown<T> extends StatefulWidget {
  final List<T> items;
  final T? value;
  final String labelText;
  final String hintText;
  final String Function(T) itemToString;
  final bool Function(T, String) filterFn;
  final ValueChanged<T?> onChanged;
  final Widget? prefixIcon;

  const SearchableDropdown({
    super.key,
    required this.items,
    this.value,
    required this.labelText,
    this.hintText = 'Search...',
    required this.itemToString,
    required this.filterFn,
    required this.onChanged,
    this.prefixIcon,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    final selectedText = widget.value != null ? widget.itemToString(widget.value as T) : '';

    return InkWell(
      onTap: () => _showSearchDialog(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: const OutlineInputBorder(),
          prefixIcon: widget.prefixIcon,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          selectedText.isEmpty ? 'Select ${widget.labelText}' : selectedText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selectedText.isEmpty ? Colors.grey.shade600 : Colors.black,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  void _showSearchDialog(BuildContext context) {
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final filteredItems = widget.items.where((item) => widget.filterFn(item, searchQuery)).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Select ${widget.labelText}'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: widget.hintText,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setStateDialog(() {
                                  searchQuery = '';
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      setStateDialog(() {
                        searchQuery = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: filteredItems.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No ${widget.labelText.toLowerCase()}s found matching "$searchQuery"',
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredItems.length,
                            itemBuilder: (context, idx) {
                              final item = filteredItems[idx];
                              final isSelected = item == widget.value;
                              return ListTile(
                                title: Text(widget.itemToString(item)),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
                                onTap: () {
                                  widget.onChanged(item);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  widget.onChanged(null);
                  Navigator.pop(context);
                },
                child: const Text('Clear Selection', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}
