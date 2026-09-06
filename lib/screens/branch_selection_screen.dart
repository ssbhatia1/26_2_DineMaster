import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../core/database/database_helper.dart';

class BranchSelectionScreen extends StatefulWidget {
  const BranchSelectionScreen({super.key});

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    final db = await DatabaseHelper.instance.database;
    final restaurants = await db.query('restaurants');
    setState(() {
      _restaurants = restaurants;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.indigo.shade900,
                  Colors.deepPurple.shade900,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // Content
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withAlpha(30),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store, size: 64, color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        'Select Branch',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose the outlet to manage',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 32),
                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : _restaurants.isEmpty
                              ? const Text('No branches found', style: TextStyle(color: Colors.white))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _restaurants.length,
                                  itemBuilder: (context, index) {
                                    final restaurant = _restaurants[index];
                                    return Card(
                                      color: Colors.white.withAlpha(25),
                                      margin: const EdgeInsets.only(bottom: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(color: Colors.white24),
                                      ),
                                      child: ListTile(
                                        title: Text(
                                          restaurant['name'],
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          restaurant['address'] ?? 'No address',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                                        onTap: () {
                                          DatabaseHelper.currentRestaurantId = restaurant['id'];
                                          context.go('/dashboard');
                                        },
                                      ),
                                    ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
                                  },
                                ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
