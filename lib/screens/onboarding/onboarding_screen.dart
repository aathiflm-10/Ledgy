import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../main.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Setup form fields (Page 3)
  late TextEditingController _nameController;
  String _selectedCurrency = 'INR';
  bool _budgetAlerts = true;
  bool _recurringReminders = true;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameController = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ── SAVE ONBOARDING PREFERENCES ────────────────────────────────────
  void _completeOnboarding() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final uid = user.uid;
    final name = _nameController.text.trim().isEmpty ? 'User' : _nameController.text.trim();

    try {
      // Save locally
      await globalPrefs.setString('currency_$uid', _selectedCurrency);
      await globalPrefs.setBool('budgetAlerts_$uid', _budgetAlerts);
      await globalPrefs.setBool('recurringReminders_$uid', _recurringReminders);
      await globalPrefs.setBool('hasOnboarded_$uid', true);

      if (context.mounted) {
        context.go('/sms-permission');
      }
    } catch (e) {
      debugPrint('Error saving onboarding: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar (Log Out & Skip)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(authServiceProvider).logout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Sign Out'),
                  ),
                  _currentPage < 2
                      ? TextButton(
                          onPressed: () => _pageController.jumpToPage(2),
                          child: const Text('Skip'),
                        )
                      : const SizedBox(width: 48, height: 48),
                ],
              ),
            ),

            // Page Slider
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildPageOne(theme),
                  _buildPageTwo(theme),
                  _buildPageThree(theme),
                ],
              ),
            ),

            // Dots & Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Page Indicators (Dots)
                  Row(
                    children: List.generate(3, (index) {
                      final active = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: active ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        decoration: BoxDecoration(
                          color: active ? theme.primaryColor : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  // Next / Start Button
                  SizedBox(
                    height: 48,
                    width: 140,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < 2) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _completeOnboarding();
                        }
                      },
                      child: Text(_currentPage < 2 ? 'Next' : 'Get Started'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PAGE BUILDERS ──────────────────────────────────────────────────
  Widget _buildPageOne(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.bolt,
            size: 100,
            color: Color(0xFF1DB87A),
          ),
          const SizedBox(height: 40),
          Text(
            'Track on autopilot',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Ledgy reads your bank transaction SMS messages automatically, extracting amounts, banks, and merchants securely.',
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPageTwo(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.pie_chart_outline_outlined,
            size: 100,
            color: Color(0xFF3B82F6),
          ),
          const SizedBox(height: 40),
          Text(
            'Understand your money',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Beautiful charts and dynamic summaries help you map categories, analyze trends, and identify potential savings.',
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPageThree(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            "Let's set you up",
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Customize your tracking experience.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Name Input
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Preferred Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 20),

          // Currency Dropdown
          DropdownButtonFormField<String>(
            value: _selectedCurrency,
            onChanged: (val) => setState(() => _selectedCurrency = val ?? 'INR'),
            decoration: const InputDecoration(
              labelText: 'Primary Currency',
              prefixIcon: Icon(Icons.currency_exchange),
            ),
            items: const [
              DropdownMenuItem(value: 'INR', child: Text('INR (₹) Indian Rupee')),
              DropdownMenuItem(value: 'USD', child: Text('USD (\$) US Dollar')),
              DropdownMenuItem(value: 'EUR', child: Text('EUR (€) Euro')),
              DropdownMenuItem(value: 'GBP', child: Text('GBP (£) British Pound')),
            ],
          ),
          const SizedBox(height: 24),

          // Notification Preferences Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preferences',
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Budget Alerts'),
                    subtitle: const Text('Notify when category spend crosses 80%'),
                    value: _budgetAlerts,
                    onChanged: (val) => setState(() => _budgetAlerts = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Recurring Reminders'),
                    subtitle: const Text('Remind me the day before bills are due'),
                    value: _recurringReminders,
                    onChanged: (val) => setState(() => _recurringReminders = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
