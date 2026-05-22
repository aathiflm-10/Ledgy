import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/auth_provider.dart';
import '../../main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      
      final user = ref.read(currentUserProvider);
      if (user == null) {
        context.go('/login');
      } else {
        final hasOnboarded = globalPrefs.getBool('hasOnboarded_${user.uid}') ?? false;
        if (!hasOnboarded) {
          context.go('/onboarding');
        } else {
          context.go('/home');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1DB87A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text(
                  'L',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1DB87A),
                  ),
                ),
              ),
            )
            .animate()
            .scale(duration: 800.ms, curve: Curves.bounceOut)
            .fadeIn(duration: 500.ms),
            const SizedBox(height: 20),
            const Text(
              'ledgy',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            )
            .animate()
            .fadeIn(delay: 400.ms, duration: 500.ms)
            .moveY(begin: 10, end: 0),
            const SizedBox(height: 8),
            Text(
              'Smart finance, automated.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            )
            .animate()
            .fadeIn(delay: 700.ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
