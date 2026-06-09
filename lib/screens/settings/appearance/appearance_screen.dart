import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_provider.dart';

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
    
    ThemeMode mode;
    switch (theme) {
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'dark':
        mode = ThemeMode.dark;
        break;
      default:
        mode = ThemeMode.system;
    }
    ref.read(themeModeProvider.notifier).state = mode;
    
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Theme set to: ${theme.toUpperCase()}'), 
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
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
