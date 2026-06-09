import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../db/app_database.dart';
import '../../providers/db_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/formatters.dart';
import '../../core/extensions.dart';
import '../../main.dart';
import '../transactions/transaction_bottom_sheet.dart';
import '../notifications/notifications_screen.dart';
import '../../services/recurring_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _currencySymbol = '₹';

  @override
  void initState() {
    super.initState();
    final uid = ref.read(currentUidProvider);
    final savedCode = globalPrefs.getString('currency_$uid') ?? 'INR';
    setState(() {
      if (savedCode == 'USD') _currencySymbol = '\$';
      else if (savedCode == 'EUR') _currencySymbol = '€';
      else if (savedCode == 'GBP') _currencySymbol = '£';
      else _currencySymbol = '₹';
    });
  }

  // ── RECONCILE RECURRING TRANSACTIONS ON LAUNCH ─────────────────────
  void _checkRecurring(AppDatabase db, String uid) async {
    final service = RecurringService(db);
    final count = await service.checkAndGenerateDueTransactions(uid);
    if (count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🔁 Generated $count scheduled payments.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    
    // Evaluate recurring schedules once db is resolved
    _checkRecurring(db, uid);

    final theme = Theme.of(context);

    // ── DATA WATCHERS ────────────────────────────────────────────────
    final transactionsStream = ref.watch(HomeScreenStreams.txnsProvider);
    final categoriesStream = ref.watch(HomeScreenStreams.catsProvider);
    final pendingSmsCountStream = ref.watch(HomeScreenStreams.pendingSmsProvider);
    final budgetsStream = ref.watch(HomeScreenStreams.budgetsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Trigger manual state reload
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                _buildHeader(theme),
                const SizedBox(height: 24),
                
                // ── BALANCES HERO ────────────────────────────────────
                transactionsStream.when(
                  data: (txns) => _buildBalanceHero(theme, txns),
                  loading: () => _buildHeroSkeleton(),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: 20),

                // ── PENDING SMS REVIEW BANNER ────────────────────────
                pendingSmsCountStream.when(
                  data: (count) => count > 0 ? _buildPendingSmsBanner(theme, count) : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // ── ACTIVE BUDGETS PROGRESS ──────────────────────────
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Budgets', style: theme.textTheme.titleMedium),
                    TextButton(
                      onPressed: () => context.push('/settings/budgets'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                budgetsStream.when(
                  data: (budgets) => transactionsStream.when(
                    data: (txns) => categoriesStream.when(
                      data: (cats) => _buildBudgetsSection(theme, budgets, txns, cats),
                      loading: () => _buildCardSkeleton(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    loading: () => _buildCardSkeleton(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  loading: () => _buildCardSkeleton(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // ── RECENT TRANSACTIONS ──────────────────────────────
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Activities', style: theme.textTheme.titleMedium),
                    TextButton(
                      onPressed: () => context.go('/transactions'),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                transactionsStream.when(
                  data: (txns) => categoriesStream.when(
                    data: (cats) => _buildRecentTransactions(theme, txns, cats),
                    loading: () => _buildCardSkeleton(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  loading: () => _buildCardSkeleton(),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => TransactionBottomSheet.show(context: context, db: db, userId: uid),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme) {
    final user = ref.watch(currentUserProvider);
    final String greetingName = user?.displayName ?? 'Guest';
    final uid = ref.watch(currentUidProvider);
    final notificationsAsync = ref.watch(notificationsProvider);
    final notifications = notificationsAsync.value ?? [];
    final readIds = ref.watch(readNotificationIdsProvider(uid));
    final unreadCount = notifications.where((n) => !readIds.contains(n.id)).length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello,',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
              Text(
                greetingName,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            backgroundColor: theme.colorScheme.error,
            child: const Icon(Icons.notifications_none_outlined, size: 28),
          ),
          onPressed: () => context.push('/notifications'),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  // ── HERO BANNER (BALANCE) ──────────────────────────────────────────
  Widget _buildBalanceHero(ThemeData theme, List<Transaction> txns) {
    double totalIncome = 0.0;
    double totalExpense = 0.0;

    for (final txn in txns) {
      if (txn.status != 'confirmed') continue;
      if (txn.type == 'income') {
        totalIncome += txn.amount;
      } else if (txn.type == 'expense') {
        totalExpense += txn.amount;
      }
    }

    final net = totalIncome - totalExpense;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withRed(10).withBlue(100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET BALANCE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.7),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.formatCurrency(net, symbol: _currencySymbol),
            style: theme.textTheme.displayLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Income capsule
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.arrow_downward, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'INCOME',
                              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold),
                            ),
                            Text(
                              Formatters.formatCurrency(totalIncome, symbol: _currencySymbol),
                              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Expense capsule
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.arrow_upward, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EXPENSES',
                              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold),
                            ),
                            Text(
                              Formatters.formatCurrency(totalExpense, symbol: _currencySymbol),
                              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 450.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── PENDING SMS CARD BANNER ────────────────────────────────────────
  Widget _buildPendingSmsBanner(ThemeData theme, int count) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: Colors.white,
            radius: 18,
            child: const Icon(Icons.sms, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Reviews',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
                ),
                Text(
                  '$count transactions detected from bank SMS need your approval.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => context.go('/sms-review'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).animate().fadeIn().moveY(begin: 10, end: 0);
  }

  // ── BUDGETS ROW ────────────────────────────────────────────────────
  Widget _buildBudgetsSection(
    ThemeData theme,
    List<Budget> budgets,
    List<Transaction> txns,
    List<Category> cats,
  ) {
    if (budgets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No monthly budgets set yet.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final now = DateTime.now();

    return Column(
      children: budgets.map((budget) {
        final cat = cats.firstWhere((c) => c.id == budget.categoryId, orElse: () => cats.first);
        
        // Sum expenses for this month for this category
        double spent = 0.0;
        for (final txn in txns) {
          if (txn.status == 'confirmed' &&
              txn.categoryId == budget.categoryId &&
              txn.type == 'expense' &&
              txn.date.month == now.month &&
              txn.date.year == now.year) {
            spent += txn.amount;
          }
        }

        final double percent = budget.limitAmount > 0 ? (spent / budget.limitAmount) : 0.0;
        final bool isAlert = percent >= 0.8;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(cat.icon, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cat.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${Formatters.formatCurrency(spent, symbol: _currencySymbol)} / ${Formatters.formatCurrency(budget.limitAmount, symbol: _currencySymbol)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isAlert ? theme.colorScheme.error : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isAlert ? theme.colorScheme.error : theme.primaryColor,
                    ),
                  ),
                ),
                if (isAlert) ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠️ Used ${(percent * 100).toStringAsFixed(0)}% of your limit!',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── RECENT TRANSACTIONS LIST ───────────────────────────────────────
  Widget _buildRecentTransactions(ThemeData theme, List<Transaction> txns, List<Category> cats) {
    final confirmed = txns.where((t) => t.status == 'confirmed').take(5).toList();

    if (confirmed.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No transaction logs recorded.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: confirmed.map((txn) {
        final cat = cats.firstWhere(
          (c) => c.id == txn.categoryId,
          orElse: () => Category(
            id: 'other',
            userId: txn.userId,
            name: 'Other',
            icon: '📌',
            color: '#64748B',
            type: 'expense',
            keywords: '',
            isCustom: false,
            isSynced: false,
            isDeleted: false,
          ),
        );

        final isExpense = txn.type == 'expense';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Color(int.parse(cat.color.replaceAll('#', '0xFF'))).withOpacity(0.12),
            child: Text(cat.icon, style: const TextStyle(fontSize: 18)),
          ),
          title: Text(
            txn.merchant ?? cat.name,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            Formatters.formatShortDate(txn.date),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: Text(
            '${isExpense ? "-" : "+"}${Formatters.formatCurrency(txn.amount, symbol: _currencySymbol)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isExpense ? theme.colorScheme.error : theme.primaryColor,
              fontSize: 14,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── SKELETONS ──────────────────────────────────────────────────────
  Widget _buildHeroSkeleton() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(24),
      ),
    ).animate().shimmer();
  }

  Widget _buildCardSkeleton() {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
    ).animate().shimmer();
  }
}

// ── REACTIVE RIVERPOD STREAMS ───────────────────────────────────────
class HomeScreenStreams {
  static final txnsProvider = StreamProvider<List<Transaction>>((ref) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    return (db.select(db.transactions)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.date)]))
        .watch();
  });

  static final catsProvider = StreamProvider<List<Category>>((ref) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    return (db.select(db.categories)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
        .watch();
  });

  static final pendingSmsProvider = StreamProvider<int>((ref) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    return (db.select(db.transactions)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.status.equals('pending') &
              tbl.source.equals('sms') &
              tbl.isDeleted.equals(false)))
        .watch()
        .map((list) => list.length);
  });

  static final budgetsProvider = StreamProvider<List<Budget>>((ref) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final now = DateTime.now();
    return (db.select(db.budgets)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.month.equals(now.month) &
              tbl.year.equals(now.year) &
              tbl.isDeleted.equals(false)))
        .watch();
  });
}
