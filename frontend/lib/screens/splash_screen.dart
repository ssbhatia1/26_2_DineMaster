import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';
import '../core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'Initializing system...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Brief pause for splash animation
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Automatically preserve and keep existing data; never prompt the user to clean data
      await prefs.setString('setup_data_choice', 'keep');

      // Initialize or connect to database
      if (mounted) {
        setState(() => _statusMessage = 'Loading restaurant data...');
      }
      await DatabaseHelper.instance.database;
      if (!mounted) return;
      await _navigateNext();
    } catch (e) {
      if (!mounted) return;
      await _navigateNext();
    }
  }

  Future<void> _navigateNext() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    final token = prefs.getString('token');
    final hasToken = rememberMe && (token != null && token.isNotEmpty);

    if (!mounted) return;
    if (hasToken) {
      context.go('/branch_selection');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Application Logo
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(40),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/logo.jpg',
                  height: 120,
                  width: 120,
                  fit: BoxFit.cover,
                ),
              ),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 500.ms),

            const SizedBox(height: 28),

            const Text(
              'DINE MASTER',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Color(0xFF1E293B),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 8),

            const Text(
              'Enterprise Restaurant POS & Management',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ).animate().fadeIn(delay: 350.ms, duration: 400.ms),

            const SizedBox(height: 48),

            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 16),

            Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
            ).animate().fadeIn(delay: 600.ms),
          ],
        ),
      ),
    );
  }
}
