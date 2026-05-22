import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_animate/flutter_animate.dart';

import '../../db/app_database.dart';
import '../../providers/db_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/formatters.dart';
import '../../core/extensions.dart';
import '../../main.dart';

import '../../services/categorization_service.dart';

class SmsReviewScreen extends ConsumerStatefulWidget {
  const SmsReviewScreen({super.key});

  @override
  ConsumerState<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends ConsumerState<SmsReviewScreen> {
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

  // ── CONFIRM TRANSACTION ────────────────────────────────────────────
  void _confirmTransaction(AppDatabase db, Transaction txn) async {
    await db.update(db.transactions).replace(
      txn.copyWith(status: 'confirmed', isSynced: false, updatedAt: DateTime.now()),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚡ Transaction approved successfully.'), duration: Duration(milliseconds: 700), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ── REJECT TRANSACTION ─────────────────────────────────────────────
  void _rejectTransaction(AppDatabase db, Transaction txn) async {
    await db.update(db.transactions).replace(
      txn.copyWith(status: 'rejected', isSynced: false, updatedAt: DateTime.now()),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Transaction dismissed/rejected.'), duration: Duration(milliseconds: 700), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ── CHANGE CATEGORY ON-THE-FLY ─────────────────────────────────────
  void _changeCategory(AppDatabase db, Transaction txn, String uid) async {
    final cats = await (db.select(db.categories)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
        .get();

    if (!mounted) return;

    final newCatId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Category'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cats.length,
            itemBuilder: (context, idx) {
              final cat = cats[idx];
              return ListTile(
                leading: Text(cat.icon, style: const TextStyle(fontSize: 18)),
                title: Text(cat.name),
                onTap: () => Navigator.pop(context, cat.id),
              );
            },
          ),
        ),
      ),
    );

    if (newCatId != null) {
      // 1. Update the category for this transaction
      await db.update(db.transactions).replace(
        txn.copyWith(categoryId: newCatId, isSynced: false),
      );

      // 2. Intelligently update KeywordMaps learning system for this merchant!
      if (txn.merchant != null) {
        final categorizer = CategorizationService(db);
        await categorizer.learnCorrection(txn.merchant!, newCatId, uid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    // Watch pending SMS transaction list reactively
    final pendingTxnsStream = ref.watch(pendingSmsTransactionsProvider);
    final catsStream = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Review Deck', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: pendingTxnsStream.when(
        data: (txns) => catsStream.when(
          data: (cats) {
            if (txns.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'All caught up!',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No pending SMS transactions to audit.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: txns.length,
              itemBuilder: (context, idx) {
                final txn = txns[idx];
                final cat = cats.firstWhere((c) => c.id == txn.categoryId, orElse: () => cats.first);

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Header: Merchant & Date
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    txn.merchant ?? 'Merchant Detect',
                                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    Formatters.formatTimestamp(txn.date),
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${txn.type == 'expense' ? "-" : "+"}${Formatters.formatCurrency(txn.amount, symbol: _currencySymbol)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: txn.type == 'expense' ? theme.colorScheme.error : theme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Interactive Category Card
                        GestureDetector(
                          onTap: () => _changeCategory(db, txn, uid),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Color(int.parse(cat.color.replaceAll('#', '0xFF'))).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Text(cat.icon, style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 8),
                                Text(
                                  cat.name,
                                  style: TextStyle(
                                    color: Color(int.parse(cat.color.replaceAll('#', '0xFF'))),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                const Text('Tap to change', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Raw SMS Body Audit Panel
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  txn.notes ?? 'No raw details.',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Confirm & Reject Actions
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _rejectTransaction(db, txn),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(color: theme.colorScheme.error.withOpacity(0.4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _confirmTransaction(db, txn),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ).animate().scale(delay: 50.ms * idx).fadeIn();
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── REACTIVE PENDING TRANSACTIONS STREAM ─────────────────────────────
final pendingSmsTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.transactions)
        ..where((tbl) =>
            tbl.userId.equals(uid) &
            tbl.status.equals('pending') &
            tbl.source.equals('sms') &
            tbl.isDeleted.equals(false))
        ..orderBy([(tbl) => drift.OrderingTerm.desc(tbl.date)]))
      .watch();
});

final categoriesListProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.categories)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
      .watch();
});
