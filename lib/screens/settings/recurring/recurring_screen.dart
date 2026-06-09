import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../../db/app_database.dart';
import '../../../providers/db_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/formatters.dart';

class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  final _uuid = const Uuid();

  // ── OPEN SET RECURRING RULE DIALOG ─────────────────────────────────
  void _openSetRuleDialog(AppDatabase db, String uid, {RecurringRule? ruleToEdit}) async {
    final cats = await (db.select(db.categories)
          ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
        .get();

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: ruleToEdit?.name ?? '');
    final amountController = TextEditingController(
      text: ruleToEdit != null ? ruleToEdit.amount.toStringAsFixed(0) : '',
    );
    String? selectedCatId = ruleToEdit?.categoryId;
    String selectedFrequency = ruleToEdit?.frequency ?? 'monthly';
    String selectedType = ruleToEdit?.type ?? 'expense';
    DateTime selectedDate = ruleToEdit?.nextDueDate ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String recurrenceText = '';
            final dayOfWeekName = DateFormat('EEEE').format(selectedDate);
            final dayOfMonth = selectedDate.day;
            final monthAndDay = DateFormat('MMMM d').format(selectedDate);

            if (selectedFrequency == 'daily') {
              recurrenceText = 'Repeats daily';
            } else if (selectedFrequency == 'weekly') {
              recurrenceText = 'Repeats weekly every $dayOfWeekName';
            } else if (selectedFrequency == 'monthly') {
              String suffix = 'th';
              if (dayOfMonth == 1 || dayOfMonth == 21 || dayOfMonth == 31) suffix = 'st';
              else if (dayOfMonth == 2 || dayOfMonth == 22) suffix = 'nd';
              else if (dayOfMonth == 3 || dayOfMonth == 23) suffix = 'rd';
              recurrenceText = 'Repeats monthly on $dayOfMonth$suffix of every month';
            } else if (selectedFrequency == 'yearly') {
              recurrenceText = 'Repeats yearly on $monthAndDay';
            }

            return AlertDialog(
              title: Text(ruleToEdit == null ? 'Set Recurring Rule' : 'Edit Recurring Rule'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        validator: (value) => value == null || value.trim().isEmpty ? 'Enter name' : null,
                        decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Netflix, Rent, Salary'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: selectedCatId,
                        onChanged: (val) => setDialogState(() => selectedCatId = val),
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter amount';
                          if (double.tryParse(value) == null || double.parse(value) <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                        decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        onChanged: (val) => setDialogState(() => selectedType = val ?? 'expense'),
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'expense', child: Text('Expense')),
                          DropdownMenuItem(value: 'income', child: Text('Income')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedFrequency,
                        onChanged: (val) => setDialogState(() {
                          selectedFrequency = val ?? 'monthly';
                          if (selectedFrequency == 'daily') {
                            selectedDate = DateTime.now();
                          }
                        }),
                        decoration: const InputDecoration(labelText: 'Frequency'),
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                        ],
                      ),
                      if (selectedFrequency != 'daily') ...[
                        const SizedBox(height: 16),
                      ],
                      if (selectedFrequency != 'daily')
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 1)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Start / Next Due Date',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM dd, yyyy').format(selectedDate),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.calendar_today, color: Colors.grey, size: 20),
                              ],
                            ),
                          ),
                        ),
                      if (recurrenceText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            recurrenceText,
                            style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate() || selectedCatId == null) return;
                    
                    final name = nameController.text.trim();
                    final amount = double.parse(amountController.text);

                    if (ruleToEdit == null) {
                      final id = _uuid.v4();
                      await db.into(db.recurringRules).insert(
                        RecurringRulesCompanion.insert(
                          id: id,
                          userId: uid,
                          name: name,
                          categoryId: selectedCatId!,
                          amount: amount,
                          type: selectedType,
                          frequency: selectedFrequency,
                          nextDueDate: selectedDate,
                          isActive: const drift.Value(true),
                          isSynced: const drift.Value(false),
                        ),
                      );
                    } else {
                      await db.update(db.recurringRules).replace(
                        ruleToEdit.copyWith(
                          name: name,
                          categoryId: selectedCatId!,
                          amount: amount,
                          type: selectedType,
                          frequency: selectedFrequency,
                          nextDueDate: selectedDate,
                          isSynced: false,
                        ),
                      );
                    }

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save Rule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final uid = ref.watch(currentUidProvider);
    final theme = Theme.of(context);

    // Watch recurring rules stream
    final rulesStream = ref.watch(rulesListProvider);
    final catsStream = ref.watch(categoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Rules', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: rulesStream.when(
        data: (rules) => catsStream.when(
          data: (cats) {
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.repeat, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No schedules active.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              itemBuilder: (context, idx) {
                final rule = rules[idx];
                final cat = cats.firstWhere((c) => c.id == rule.categoryId, orElse: () => cats.first);

                return Dismissible(
                  key: Key(rule.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  onDismissed: (_) async {
                    await (db.update(db.recurringRules)..where((tbl) => tbl.id.equals(rule.id))).write(
                      const RecurringRulesCompanion(isDeleted: drift.Value(true)),
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(int.parse(cat.color.replaceAll('#', '0xFF'))).withOpacity(0.12),
                        child: Text(cat.icon, style: const TextStyle(fontSize: 18)),
                      ),
                      title: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${rule.frequency.toUpperCase()} - ${Formatters.formatCurrency(rule.amount)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openSetRuleDialog(db, uid, ruleToEdit: rule),
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
        onPressed: () => _openSetRuleDialog(db, uid),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── REACTIVE RULES STREAM ────────────────────────────────────────────
final rulesListProvider = StreamProvider<List<RecurringRule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.recurringRules)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
      .watch();
});

final categoriesListProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(currentUidProvider);
  return (db.select(db.categories)
        ..where((tbl) => tbl.userId.equals(uid) & tbl.isDeleted.equals(false)))
      .watch();
});
