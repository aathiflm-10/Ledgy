import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../db/app_database.dart';
import '../../providers/db_provider.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';
import '../settings/recurring/recurring_screen.dart';
import '../../main.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String route;
  final DateTime? date;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.route,
    this.date,
  });
}

// ── NOTIFICATIONS COMBINED STREAM PROVIDER ────────────────────────────
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final txnsAsync = ref.watch(HomeScreenStreams.txnsProvider);
  final rulesAsync = ref.watch(rulesListProvider);
  final budgetsAsync = ref.watch(HomeScreenStreams.budgetsProvider);
  final catsAsync = ref.watch(HomeScreenStreams.catsProvider);

  if (txnsAsync.isLoading || rulesAsync.isLoading || budgetsAsync.isLoading || catsAsync.isLoading) {
    return const Stream.empty();
  }

  final txns = txnsAsync.value ?? [];
  final rules = rulesAsync.value ?? [];
  final budgets = budgetsAsync.value ?? [];
  final cats = catsAsync.value ?? [];

  final List<AppNotification> list = [];

  // 1. Pending SMS Review
  final pendingSmsCount = txns.where((t) => t.status == 'pending' && t.source == 'sms').length;
  if (pendingSmsCount > 0) {
    list.add(
      AppNotification(
        id: 'pending_sms_$pendingSmsCount',
        title: 'Review SMS Transactions',
        body: 'You have $pendingSmsCount new transaction${pendingSmsCount > 1 ? 's' : ''} detected from bank SMS. Tap here to confirm.',
        icon: Icons.sms_outlined,
        iconColor: Colors.amber.shade800,
        backgroundColor: Colors.amber.shade50,
        route: '/sms-review',
      ),
    );
  }

  // 2. Upcoming Recurring Payments
  final now = DateTime.now();
  final nextWeek = now.add(const Duration(days: 7));
  for (final rule in rules) {
    if (rule.isActive && !rule.isDeleted) {
      final dueDate = rule.nextDueDate;
      if (dueDate.isAfter(now.subtract(const Duration(days: 1))) && dueDate.isBefore(nextWeek)) {
        final formattedDate = DateFormat('MMM dd').format(dueDate);
        list.add(
          AppNotification(
            id: 'recurring_${rule.id}_${dueDate.millisecondsSinceEpoch}',
            title: 'Upcoming Recurring Payment',
            body: rule.type == 'expense'
                ? 'Your recurring transaction - ${rule.name} of ₹${rule.amount.toStringAsFixed(0)} is due on $formattedDate.'
                : 'Your recurring transaction - ${rule.name} of ₹${rule.amount.toStringAsFixed(0)} is expected on $formattedDate.',
            icon: Icons.event_repeat_outlined,
            iconColor: Colors.blue.shade800,
            backgroundColor: Colors.blue.shade50,
            route: '/settings/recurring',
            date: dueDate,
          ),
        );
      }
    }
  }

  // 3. Budgets Alerts
  for (final budget in budgets) {
    if (!budget.isDeleted) {
      final cat = cats.firstWhere(
        (c) => c.id == budget.categoryId,
        orElse: () => Category(
          id: '',
          userId: '',
          name: 'Category',
          icon: '📊',
          color: '#888888',
          type: 'expense',
          keywords: '[]',
          isCustom: false,
          isSynced: false,
          isDeleted: false,
        ),
      );

      double spent = 0.0;
      for (final txn in txns) {
        if (txn.categoryId == budget.categoryId &&
            txn.status == 'confirmed' &&
            txn.type == 'expense' &&
            txn.date.month == budget.month &&
            txn.date.year == budget.year) {
          spent += txn.amount;
        }
      }

      final limit = budget.limitAmount;
      if (limit > 0) {
        final percent = (spent / limit) * 100;
        if (percent >= budget.alertAtPercent) {
          list.add(
            AppNotification(
              id: 'budget_${budget.id}_${budget.month}_${budget.year}_${percent.toStringAsFixed(0)}',
              title: percent >= 100 ? 'Budget Limit Exceeded' : 'Budget Limit Warning',
              body: percent >= 100
                  ? 'Budget pending: You have exceeded your ₹${limit.toStringAsFixed(0)} budget limit for ${cat.icon} ${cat.name} (Spent: ₹${spent.toStringAsFixed(0)}).'
                  : 'Budget pending: You have used ${percent.toStringAsFixed(0)}% of your ₹${limit.toStringAsFixed(0)} budget for ${cat.icon} ${cat.name} (Spent: ₹${spent.toStringAsFixed(0)}).',
              icon: percent >= 100 ? Icons.error_outline : Icons.warning_amber_outlined,
              iconColor: percent >= 100 ? Colors.red.shade800 : Colors.orange.shade800,
              backgroundColor: percent >= 100 ? Colors.red.shade50 : Colors.orange.shade50,
              route: '/settings/budgets',
            ),
          );
        }
      }
    }
  }

  // Sort upcoming alerts
  return Stream.value(list);
});

// ── READ NOTIFICATIONS STORAGE AND NOTIFIER ───────────────────────────
final readNotificationIdsProvider = StateNotifierProvider.family<ReadNotificationIdsNotifier, List<String>, String>((ref, uid) {
  return ReadNotificationIdsNotifier(uid);
});

class ReadNotificationIdsNotifier extends StateNotifier<List<String>> {
  final String uid;
  ReadNotificationIdsNotifier(this.uid) : super([]) {
    _load();
  }

  void _load() {
    state = globalPrefs.getStringList('readNotifications_$uid') ?? [];
  }

  void markAsRead(List<String> ids) {
    final updated = List<String>.from(state);
    bool changed = false;
    for (final id in ids) {
      if (!updated.contains(id)) {
        updated.add(id);
        changed = true;
      }
    }
    if (changed) {
      state = updated;
      globalPrefs.setStringList('readNotifications_$uid', updated);
    }
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notificationsAsync = ref.watch(notificationsProvider);

    // Auto mark as read on screen display
    notificationsAsync.whenData((list) {
      if (list.isNotEmpty) {
        final uid = ref.read(currentUidProvider);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(readNotificationIdsProvider(uid).notifier).markAsRead(
            list.map((n) => n.id).toList(),
          );
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: notificationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 48,
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'All caught up!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No important alerts at this moment.',
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final tileBg = isDark
                  ? Colors.grey.shade900
                  : item.backgroundColor;
              final borderCol = isDark
                  ? theme.dividerColor
                  : item.iconColor.withOpacity(0.15);

              return Card(
                elevation: 0,
                color: tileBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: borderCol, width: 1.5),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    // Navigate to the target route
                    if (item.route == '/sms-review') {
                      context.go(item.route);
                    } else {
                      context.push(item.route);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: isDark
                              ? item.iconColor.withOpacity(0.15)
                              : item.iconColor.withOpacity(0.1),
                          foregroundColor: item.iconColor,
                          radius: 22,
                          child: Icon(item.icon, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.body,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: (index * 80).ms).moveY(begin: 10, end: 0);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading alerts: $err')),
      ),
    );
  }
}
