import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import '../../../providers/db_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/formatters.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  final _uuid = const Uuid();

  // ── OPEN SET BUDGET DIALOG ─────────────────────────────────────────
  void _openSetBudgetDialog(AppDatabase db, String uid, {Budget? budgetToEdit}) async {
    final rawCats = await (db.select(db.categories)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
        .get();

    final excludedNames = {'salary', 'transfer', 'gifts & cashbacks', 'gifts', 'cashback'};
    final cats = rawCats.where((cat) {
      final nameLower = cat.name.toLowerCase().trim();
      return !excludedNames.contains(nameLower);
    }).toList();

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: budgetToEdit != null ? budgetToEdit.limitAmount.toStringAsFixed(0) : '',
    );
    String? selectedCatId = budgetToEdit?.categoryId;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(budgetToEdit == null ? 'Set Budget Limit' : 'Edit Budget Limit'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedCatId,
                  onChanged: budgetToEdit != null ? null : (val) => selectedCatId = val,
                  validator: (value) => value == null ? 'Select category' : null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: cats.map((cat) {
                    return DropdownMenuItem(
                      value: cat.id,
                      child: Row(
                        children: [
                          Text(cat.icon),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cat.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter amount limit';
                    if (double.tryParse(value) == null || double.parse(value) <= 0) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Monthly Limit Amount',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate() || selectedCatId == null) return;
                final limit = double.parse(amountController.text);
                final now = DateTime.now();

                if (budgetToEdit == null) {
                  // Insert
                  final id = _uuid.v4();
                  await db.into(db.budgets).insert(
                    BudgetsCompanion.insert(
                      id: id,
                      userId: uid,
                      categoryId: selectedCatId!,
                      month: now.month,
                      year: now.year,
                      limitAmount: limit,
                      alertAtPercent: const drift.Value(80),
                      isSynced: const drift.Value(false),
                    ),
                  );
                } else {
                  // Update
                  await db.update(db.budgets).replace(
                    budgetToEdit.copyWith(limitAmount: limit, isSynced: false),
                  );
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save Limit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    // Watch budgets and categories streams
    final budgetsStream = ref.watch(budgetsListProvider);
    final catsStream = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Budgets', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: budgetsStream.when(
        data: (budgets) => catsStream.when(
          data: (cats) {
            if (budgets.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.currency_exchange, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No monthly limits configured.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: budgets.length,
              itemBuilder: (context, idx) {
                final budget = budgets[idx];
                final cat = cats.firstWhere((c) => c.id == budget.categoryId, orElse: () => cats.first);

                return Dismissible(
                  key: Key(budget.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  onDismissed: (_) async {
                    await (db.update(db.budgets)..where((tbl) => tbl.id.equals(budget.id))).write(
                      const BudgetsCompanion(isDeleted: drift.Value(true)),
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(int.parse(cat.color.replaceAll('#', '0xFF'))).withOpacity(0.12),
                        child: Text(cat.icon, style: const TextStyle(fontSize: 18)),
                      ),
                      title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Limit: ${Formatters.formatCurrency(budget.limitAmount)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openSetBudgetDialog(db, uid, budgetToEdit: budget),
                      ),
                    ),
                  ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSetBudgetDialog(db, uid),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── REACTIVE BUDGETS STREAM ──────────────────────────────────────────
final budgetsListProvider = StreamProvider<List<Budget>>((ref) {
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

final categoriesListProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.categories)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
      .watch();
});
