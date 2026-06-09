import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // ── EDIT PROFILE NAME DIALOG ───────────────────────────────────────
  void _showEditNameDialog(BuildContext context, WidgetRef ref, String currentName) {
    final nameController = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile Name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Preferred Name',
              hintText: 'Enter your name',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name cannot be empty';
              }
              if (value.trim().length < 2) {
                return 'Name is too short';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newName = nameController.text.trim();
              Navigator.pop(context);
              try {
                await ref.read(authServiceProvider).updateDisplayName(newName);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile name updated successfully.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update name: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── TRIGGER ACCOUNT DELETION ───────────────────────────────────────
  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'WARNING: This is permanent. All transactions, budgets, goals, and '
          'your local database file will be permanently destroyed. Are you sure?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(authServiceProvider).deleteAccount();
                if (context.mounted) {
                  context.go('/login');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── USER INFO BANNER ───────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.primaryColor.withOpacity(0.12),
                    radius: 28,
                    child: Text(
                      user?.displayName != null && user!.displayName!.isNotEmpty
                          ? user.displayName!.substring(0, 1).toUpperCase()
                          : 'U',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.primaryColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user?.displayName ?? 'User Profile',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.grey),
                              onPressed: () => _showEditNameDialog(context, ref, user?.displayName ?? ''),
                            ),
                          ],
                        ),
                        Text(
                          user?.email ?? 'offline@ledgy.com',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── FINANCIAL PREFERENCES ──────────────────────────────────
          Text('Preferences', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildSettingsTile(
            icon: Icons.currency_exchange,
            title: 'Monthly Budgets',
            subtitle: 'Set limits for food, shopping, transit',
            onTap: () => context.push('/settings/budgets'),
          ),
          _buildSettingsTile(
            icon: Icons.track_changes,
            title: 'Savings Goals',
            subtitle: 'Track progress for milestones',
            onTap: () => context.push('/settings/goals'),
          ),
          _buildSettingsTile(
            icon: Icons.repeat,
            title: 'Recurring Rules',
            subtitle: 'Subscriptions, salaries, utility schedules',
            onTap: () => context.push('/settings/recurring'),
          ),
          
          const SizedBox(height: 24),

          // ── SYSTEM CONFIGURATIONS ──────────────────────────────────
          Text('System', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildSettingsTile(
            icon: Icons.sms_outlined,
            title: 'SMS Auto-Detection',
            subtitle: 'Real-time bank intercept parameters',
            onTap: () => context.push('/settings/sms'),
          ),
          _buildSettingsTile(
            icon: Icons.color_lens_outlined,
            title: 'Theme',
            subtitle: 'Choose dark or light mode',
            onTap: () => context.push('/settings/appearance'),
          ),

          const SizedBox(height: 24),

          // ── DANGER ZONE & SESSION ──────────────────────────────────
          Text('Account & Session', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          
          // Log Out
          ListTile(
            leading: const Icon(Icons.logout_outlined, color: Colors.grey),
            title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () async {
              await ref.read(authServiceProvider).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          
          // Delete Account
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade600),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
