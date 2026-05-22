import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../../providers/auth_provider.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  String _selectedTheme = 'system';

  @override
  void initState() {
    super.initState();
    _selectedTheme = globalPrefs.getString('selectedTheme') ?? 'system';
  }

  void _saveTheme(String theme) async {
    setState(() => _selectedTheme = theme);
    await globalPrefs.setString('selectedTheme', theme);
    
    // In a full implementation, you'd trigger a state notifier 
    // to dynamically rebuild MaterialApp with the selected theme.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Theme set to: ${theme.toUpperCase()} (Changes apply on restart)'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('System Default'),
                  subtitle: const Text('Matches your phone settings'),
                  value: 'system',
                  groupValue: _selectedTheme,
                  onChanged: (val) => _saveTheme(val ?? 'system'),
                  activeColor: theme.primaryColor,
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Light Mode'),
                  subtitle: const Text('Clean white appearance'),
                  value: 'light',
                  groupValue: _selectedTheme,
                  onChanged: (val) => _saveTheme(val ?? 'light'),
                  activeColor: theme.primaryColor,
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Sleek black aesthetic'),
                  value: 'dark',
                  groupValue: _selectedTheme,
                  onChanged: (val) => _saveTheme(val ?? 'dark'),
                  activeColor: theme.primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
