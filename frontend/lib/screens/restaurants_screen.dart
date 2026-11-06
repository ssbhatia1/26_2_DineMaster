
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../repositories/restaurant_repository.dart';
import '../services/sync_service.dart';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  final RestaurantRepository _repo = RestaurantRepository();

  List<Map<String, dynamic>> _restaurants = [];
  bool _isLoading = true;
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();

    // Keep the list in sync when other screens modify restaurant data.
    _syncSubscription = SyncService.instance.syncEvents.listen((event) {
      if (mounted && event.contains('restaurant')) {
        _loadRestaurants();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRestaurants() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final list = await _repo.getRestaurants();

      if (!mounted) return;

      setState(() {
        _restaurants = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load restaurants: $e')),
      );
    }
  }

  void _showAddRestaurantDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Restaurant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Restaurant Name',
              ),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                try {
                  await _repo.createRestaurant(
                    name: nameController.text.trim(),
                    address: addressController.text.trim(),
                    phone: phoneController.text.trim(),
                  );

                  if (context.mounted) Navigator.pop(context);
                  _loadRestaurants();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding restaurant: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditRestaurantDialog(Map<String, dynamic> restaurant) {
    final nameController =
        TextEditingController(text: restaurant['name']?.toString() ?? '');
    final addressController =
        TextEditingController(text: restaurant['address']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: restaurant['phone']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Restaurant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Restaurant Name',
              ),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                try {
                  await _repo.updateRestaurant(
                    id: (restaurant['id'] as num).toInt(),
                    name: nameController.text.trim(),
                    address: addressController.text.trim(),
                    phone: phoneController.text.trim(),
                  );

                  if (context.mounted) Navigator.pop(context);
                  _loadRestaurants();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating restaurant: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRestaurant(int id) async {
    // Count linked records before deleting.
    try {
      final counts = await _repo.getLinkedRecordCounts(id);

      final totalLinked = (counts['tables'] ?? 0) +
          (counts['products'] ?? 0) +
          (counts['orders'] ?? 0);

      if (totalLinked > 0 && mounted) {
        final parts = <String>[];

        if ((counts['tables'] ?? 0) > 0) {
          parts.add('${counts['tables']} table(s)');
        }
        if ((counts['products'] ?? 0) > 0) {
          parts.add('${counts['products']} product(s)');
        }
        if ((counts['orders'] ?? 0) > 0) {
          parts.add('${counts['orders']} order(s)');
        }

        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Warning: Linked Data Found'),
            content: Text(
              'This restaurant has ${parts.join(', ')} linked to it. '
              'Deleting it may leave orphaned data. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete Anyway'),
              ),
            ],
          ),
        );

        if (proceed != true) return;
      }

      await _repo.deleteRestaurant(id);
      _loadRestaurants();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting restaurant: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRestaurants,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('No restaurants found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _restaurants.length,
                  itemBuilder: (context, index) {
                    final restaurant = _restaurants[index];

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: const Icon(
                            Icons.restaurant,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          restaurant['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          restaurant['address']?.toString() ?? 'No address',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.grey,
                              ),
                              onPressed: () =>
                                  _showEditRestaurantDialog(restaurant),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Restaurant'),
                                    content: const Text(
                                      'Are you sure you want to delete this '
                                      'restaurant? This might affect linked data.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteRestaurant(
                                            (restaurant['id'] as num).toInt(),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddRestaurantDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
