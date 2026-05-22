import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:drift/drift.dart' as drift;

import '../../db/app_database.dart';
import '../../providers/db_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/formatters.dart';
import '../../core/extensions.dart';
import 'transaction_bottom_sheet.dart';
import '../../main.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _searchQuery = '';
  String _selectedType = 'all'; // 'all' | 'expense' | 'income'
  String _currencySymbol = '₹';

  // Multi-Selection State
  final Set<String> _selectedTxnIds = {};
  bool _isSelectionMode = false;

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

  // ── TRIGGER BULK DELETE ────────────────────────────────────────────
  void _bulkDelete(AppDatabase db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Bulk Delete'),
        content: Text('Are you sure you want to delete ${_selectedTxnIds.length} selected transactions?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await db.transaction(() async {
        for (final id in _selectedTxnIds) {
          // Soft Delete by setting isDeleted=true
          await (db.update(db.transactions)..where((tbl) => tbl.id.equals(id))).write(
            const TransactionsCompanion(isDeleted: drift.Value(true)),
          );
        }
      });

      setState(() {
        _selectedTxnIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  // ── TRIGGER BULK RE-CATEGORIZE ─────────────────────────────────────
  void _bulkRecategorize(AppDatabase db, String uid) async {
    final cats = await (db.select(db.categories)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
        .get();

    if (!mounted) return;

    final selectedCatId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk Categorize'),
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

    if (selectedCatId != null) {
      await db.transaction(() async {
        for (final id in _selectedTxnIds) {
          await (db.update(db.transactions)..where((tbl) => tbl.id.equals(id))).write(
            TransactionsCompanion(categoryId: drift.Value(selectedCatId)),
          );
        }
      });

      setState(() {
        _selectedTxnIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    // Watch all data reactively
    final txnsAsync = ref.watch(transactionsListProvider);
    final catsAsync = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedTxnIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold))
            : const Text('Ledger', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.category_outlined),
                  onPressed: () => _bulkRecategorize(db, uid),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _bulkDelete(db),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedTxnIds.clear();
                      _isSelectionMode = false;
                    });
                  },
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // ── FILTER & SEARCH PANEL ──────────────────────────────────
          if (!_isSelectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search Swiggy, rent, groceries...',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildTypeFilterChip('all', 'All Logs'),
                      const SizedBox(width: 8),
                      _buildTypeFilterChip('expense', 'Expenses'),
                      const SizedBox(width: 8),
                      _buildTypeFilterChip('income', 'Income'),
                    ],
                  ),
                ],
              ),
            ),

          // ── TRANSACTIONS LIST ──────────────────────────────────────
          Expanded(
            child: txnsAsync.when(
              data: (txns) => catsAsync.when(
                data: (cats) {
                  // Apply UI Filters
                  var filtered = txns.where((txn) {
                    final cat = cats.firstWhere((c) => c.id == txn.categoryId, orElse: () => cats.first);
                    final query = _searchQuery.toLowerCase();
                    final matchQuery = txn.merchant?.toLowerCase().contains(query) == true ||
                        txn.notes?.toLowerCase().contains(query) == true ||
                        cat.name.toLowerCase().contains(query);

                    if (!matchQuery) return false;

                    if (_selectedType == 'expense') return txn.type == 'expense';
                    if (_selectedType == 'income') return txn.type == 'income';
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return _buildEmptyState(theme);
                  }

                  // Group by Day
                  final Map<String, List<Transaction>> grouped = {};
                  for (final txn in filtered) {
                    final dayKey = _getDayKey(txn.date);
                    if (!grouped.containsKey(dayKey)) {
                      grouped[dayKey] = [];
                    }
                    grouped[dayKey]!.add(txn);
                  }

                  final keys = grouped.keys.toList();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: keys.length,
                    itemBuilder: (context, idx) {
                      final dayKey = keys[idx];
                      final dayTxns = grouped[dayKey]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sticky Header
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              dayKey,
                              style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                            ),
                          ),
                          ...dayTxns.map((txn) {
                            final cat = cats.firstWhere((c) => c.id == txn.categoryId, orElse: () => cats.first);
                            final isSelected = _selectedTxnIds.contains(txn.id);

                            return Dismissible(
                              key: Key(txn.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.delete_outline, color: Colors.red),
                              ),
                              onDismissed: (_) async {
                                await (db.update(db.transactions)..where((tbl) => tbl.id.equals(txn.id))).write(
                                  const TransactionsCompanion(isDeleted: drift.Value(true)),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Transaction deleted.'), behavior: SnackBarBehavior.floating),
                                  );
                                }
                              },
                              child: GestureDetector(
                                onLongPress: () {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedTxnIds.add(txn.id);
                                  });
                                },
                                onTap: () {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedTxnIds.remove(txn.id);
                                        if (_selectedTxnIds.isEmpty) {
                                          _isSelectionMode = false;
                                        }
                                      } else {
                                        _selectedTxnIds.add(txn.id);
                                      }
                                    });
                                  } else {
                                    TransactionBottomSheet.show(
                                      context: context,
                                      db: db,
                                      userId: uid,
                                      transactionToEdit: txn,
                                    );
                                  }
                                },
                                child: Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: isSelected
                                          ? theme.primaryColor
                                          : theme.dividerColor.withOpacity(0.08),
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Color(int.parse(cat.color.replaceAll('#', '0xFF'))).withOpacity(0.12),
                                      child: Text(cat.icon, style: const TextStyle(fontSize: 18)),
                                    ),
                                    title: Text(
                                      txn.merchant ?? cat.name,
                                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      txn.notes ?? 'Manual Entry',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(
                                      '${txn.type == 'expense' ? "-" : "+"}${Formatters.formatCurrency(txn.amount, symbol: _currencySymbol)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: txn.type == 'expense' ? theme.colorScheme.error : theme.primaryColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  // ── FILTER CHIP BUILDER ────────────────────────────────────────────
  Widget _buildTypeFilterChip(String type, String label) {
    final active = _selectedType == type;
    final theme = Theme.of(context);

    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedType = type);
          }
        },
        selectedColor: theme.primaryColor.withOpacity(0.12),
        labelStyle: TextStyle(
          color: active ? theme.primaryColor : Colors.grey.shade600,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        showCheckmark: false,
      ),
    );
  }

  // ── EMPTY STATE ────────────────────────────────────────────────────
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No matching records', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
        ],
      ),
    );
  }

  String _getDayKey(DateTime date) {
    if (date.isToday) return 'TODAY';
    if (date.isYesterday) return 'YESTERDAY';
    return DateFormat('EEEE, d MMMM').format(date).toUpperCase();
  }
}

// ── REACTIVE RIVERPOD STREAMS ───────────────────────────────────────
final transactionsListProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.transactions)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false) & tbl.status.equals('confirmed'))
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
