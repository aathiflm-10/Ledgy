import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../../db/app_database.dart';
import '../../../providers/db_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/formatters.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  final _uuid = const Uuid();

  // ── OPEN SET GOAL DIALOG ───────────────────────────────────────────
  void _openSetGoalDialog(AppDatabase db, String uid, {SavingsGoal? goalToEdit}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: goalToEdit?.name ?? '');
    final targetController = TextEditingController(text: goalToEdit != null ? goalToEdit.targetAmount.toStringAsFixed(0) : '');
    final currentController = TextEditingController(text: goalToEdit != null ? goalToEdit.currentAmount.toStringAsFixed(0) : '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(goalToEdit == null ? 'Set Savings Goal' : 'Edit Savings Goal'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter goal name' : null,
                    decoration: const InputDecoration(labelText: 'Goal Name', hintText: 'e.g. Buy a Laptop, Vacation'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: targetController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Enter target amount';
                      if (double.tryParse(value) == null || double.parse(value) <= 0) {
                        return 'Enter a valid amount';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(labelText: 'Target Amount', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: currentController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Enter saved amount';
                      if (double.tryParse(value) == null || double.parse(value) < 0) {
                        return 'Enter a valid amount';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(labelText: 'Saved Amount', prefixText: '₹ '),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                
                final name = nameController.text.trim();
                final target = double.parse(targetController.text);
                final current = double.parse(currentController.text);

                if (goalToEdit == null) {
                  final id = _uuid.v4();
                  await db.into(db.savingsGoals).insert(
                    SavingsGoalsCompanion.insert(
                      id: id,
                      userId: uid,
                      name: name,
                      targetAmount: target,
                      currentAmount: drift.Value(current),
                      icon: '🎯',
                      color: '#1DB87A',
                      isSynced: const drift.Value(false),
                      createdAt: DateTime.now(),
                    ),
                  );
                } else {
                  await db.update(db.savingsGoals).replace(
                    goalToEdit.copyWith(
                      name: name,
                      targetAmount: target,
                      currentAmount: current,
                      isSynced: false,
                    ),
                  );
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save Goal'),
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

    // Watch savings goals stream
    final goalsStream = ref.watch(goalsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings Goals', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: goalsStream.when(
        data: (goals) {
          if (goals.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.track_changes, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No savings milestones logged.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: goals.length,
            itemBuilder: (context, idx) {
              final goal = goals[idx];
              final double percent = goal.targetAmount > 0 ? (goal.currentAmount / goal.targetAmount) : 0.0;

              return Dismissible(
                key: Key(goal.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_outline, color: Colors.red),
                ),
                onDismissed: (_) async {
                  await (db.update(db.savingsGoals)..where((tbl) => tbl.id.equals(goal.id))).write(
                    const SavingsGoalsCompanion(isDeleted: drift.Value(true)),
                  );
                },
                child: Card(
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
                                  Text(goal.icon, style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      goal.name,
                                      style: theme.textTheme.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _openSetGoalDialog(db, uid, goalToEdit: goal),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progress: ${(percent * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${Formatters.formatCurrency(goal.currentAmount)} / ${Formatters.formatCurrency(goal.targetAmount)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                          ),
                        ),
                      ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSetGoalDialog(db, uid),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── REACTIVE GOALS STREAM ────────────────────────────────────────────
final goalsListProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.savingsGoals)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
      .watch();
});
