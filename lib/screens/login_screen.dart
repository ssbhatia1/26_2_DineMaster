import 'dart:ui';
import 'package:nexodine/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _selectedRole = 'Owner';

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
                  AppColors.primary,
                  AppColors.navyBlue100.withAlpha(50),
                  AppColors.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // Decorative Circles
          Positioned(
            top: -100,
            left: -100,
            child: CircleAvatar(
              radius: 200,
              backgroundColor: Colors.white.withAlpha(25),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: CircleAvatar(
              radius: 250,
              backgroundColor: Colors.blue.withAlpha(25),
            ),
          ),

          // Login Form
          Center(
            child: SingleChildScrollView(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xE6040E21),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withAlpha(45),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo or App Name
                        Image.asset(
                          'assets/images/logo.jpg',
                          height: 120,
                        ).animate().scale(delay: 200.ms, duration: 500.ms, curve: Curves.easeOutBack),
                        const SizedBox(height: 16),
                        const Text(
                          'DINE MASTER',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ).animate().fadeIn(delay: 400.ms),
                        const Text(
                          'Enterprise ERP & POS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ).animate().fadeIn(delay: 600.ms),
                        const SizedBox(height: 40),

                        // Username Field
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: const TextStyle(color: Colors.white70),
                            prefixIcon: const Icon(Icons.person, color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withAlpha(40),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withAlpha(70)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ).animate().fadeIn(delay: 800.ms).slideX(begin: -0.1),
                        const SizedBox(height: 20),

                        // Password Field
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Colors.white70),
                            prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: Colors.white.withAlpha(40),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withAlpha(70)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ).animate().fadeIn(delay: 1000.ms).slideX(begin: 0.1),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          value: _selectedRole,
                          dropdownColor: AppColors.primaryMaterialColor[800]!,
                          style: const TextStyle(color: Colors.white),
                          items: ['Owner', 'Manager', 'Cashier', 'Waiter', 'Chef']
                              .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(color: Colors.white))))
                              .toList(),
                          onChanged: (val) => setState(() => _selectedRole = val!),
                          decoration: InputDecoration(
                            labelText: 'Role',
                            labelStyle: const TextStyle(color: Colors.white70),
                            prefixIcon: const Icon(Icons.badge, color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withAlpha(40),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withAlpha(70)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ).animate().fadeIn(delay: 1100.ms).slideX(begin: -0.1),
                        const SizedBox(height: 12),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {},
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ).animate().fadeIn(delay: 1200.ms),
                        const SizedBox(height: 24),

                        // Login Button
                        ElevatedButton(
                          onPressed: () async {
                            final username = _usernameController.text.trim();
                            final password = _passwordController.text.trim();

                            if (username.isEmpty || password.isEmpty) {
                              if(false) ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill all fields')),
                              );
                              return;
                            }

                            final db = await DatabaseHelper.instance.database;
                            final users = await db.query(
                              'users',
                              where: 'username = ? AND password = ? AND role = ?',
                              whereArgs: [username, DatabaseHelper.hashPassword(password), _selectedRole],
                            );

                            if (users.isNotEmpty) {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('token', 'mock_token_123');
                              await prefs.setString('username', username);
                              await prefs.setString('role', _selectedRole);
                              context.go('/branch_selection');
                            } else {
                              if(false) ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid credentials or role')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primaryMaterialColor[900]!,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: const Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ).animate().fadeIn(delay: 1400.ms).scale(begin: const Offset(0.9, 0.9)),
                        const SizedBox(height: 16),

                        // Register Option
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                            TextButton(
                              onPressed: () => _showRegisterDialog(),
                              child: const Text('Register', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ).animate().fadeIn(delay: 1500.ms),
                        const SizedBox(height: 16),

                        // Role selection or info
                        const Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(Icons.info_outline, color: Colors.white60, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Default: owner/owner123',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ).animate().fadeIn(delay: 1600.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRegisterDialog() {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'Waiter';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  items: ['Owner', 'Manager', 'Cashier', 'Waiter', 'Chef']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) => setState(() => role = val!),
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text.trim();

                if (name.isEmpty || username.isEmpty || password.isEmpty) {
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                try {
                  final db = await DatabaseHelper.instance.database;
                  await db.insert('users', {
                    'name': name,
                    'username': username,
                    'password': DatabaseHelper.hashPassword(password),
                    'role': role,
                    'is_active': 1,
                    'created_at': DateTime.now().toIso8601String(),
                  });
                  Navigator.pop(context);
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account created successfully!')),
                  );
                } catch (e) {
                  if(false) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating account: $e')),
                  );
                }
              },
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}
