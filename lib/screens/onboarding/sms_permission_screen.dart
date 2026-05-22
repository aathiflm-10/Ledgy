import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsPermissionScreen extends ConsumerStatefulWidget {
  const SmsPermissionScreen({super.key});

  @override
  ConsumerState<SmsPermissionScreen> createState() => _SmsPermissionScreenState();
}

class _SmsPermissionScreenState extends ConsumerState<SmsPermissionScreen> {
  bool _isLoading = false;

  // ── REQUEST PERMISSION ─────────────────────────────────────────────
  void _requestSmsPermission() async {
    setState(() => _isLoading = true);

    try {
      final status = await Permission.sms.request();
      
      if (status.isGranted) {
        // SMS Access granted! Trigger historical sweep
        // We will call the native SmsFetcher channel here in later Phase integrations
        debugPrint('SMS Permission granted. Historical sweep triggered.');
      } else {
        debugPrint('SMS Permission denied by user.');
      }
    } catch (e) {
      debugPrint('SMS Permission error: $e');
    } finally {
      setState(() => _isLoading = false);
      if (mounted) {
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.sms_outlined,
                    size: 72,
                    color: theme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                'Never miss a transaction',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Explanation
              Text(
                'Ledgy scans your incoming SMS in real-time to log transaction details on autopilot. No manual input, no credit card linking.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Privacy Notice Card
              Card(
                color: Colors.amber.shade50.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.amber.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Strict Privacy Guarantee',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.amber.shade900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'We only parse financial transaction messages from bank senders. Your personal text messages are never read, stored, or sent to any server.',
                              style: TextStyle(
                                color: Colors.amber.shade900.withOpacity(0.8),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Allow SMS Access Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestSmsPermission,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Allow SMS Access'),
                ),
              ),
              const SizedBox(height: 16),

              // Skip Button
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Skip for now',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
