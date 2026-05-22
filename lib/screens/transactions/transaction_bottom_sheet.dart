import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

class TransactionBottomSheet extends StatefulWidget {
  final AppDatabase db;
  final String userId;
  final Transaction? transactionToEdit;

  const TransactionBottomSheet({
    super.key,
    required this.db,
    required this.userId,
    this.transactionToEdit,
  });

  static void show({
    required BuildContext context,
    required AppDatabase db,
    required String userId,
    Transaction? transactionToEdit,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: TransactionBottomSheet(
          db: db,
          userId: userId,
          transactionToEdit: transactionToEdit,
        ),
      ),
    );
  }

  @override
  State<TransactionBottomSheet> createState() => _TransactionBottomSheetState();
}

class _TransactionBottomSheetState extends State<TransactionBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  // Form states
  late String _type; // 'expense' | 'income'
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  
  String? _selectedCategoryId;
  late DateTime _selectedDate;
  List<Category> _categories = [];
  bool _isLoadingCategories = true;

  @override
  void initState() {
    super.initState();
    final txn = widget.transactionToEdit;

    _type = txn?.type ?? 'expense';
    _amountController.text = txn != null ? txn.amount.toStringAsFixed(2) : '';
    _merchantController.text = txn?.merchant ?? '';
    _notesController.text = txn?.notes ?? '';
    _selectedCategoryId = txn?.categoryId;
    _selectedDate = txn?.date ?? DateTime.now();

    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── LOAD USER CATEGORIES FROM DATABASE ──────────────────────────────
  void _loadCategories() async {
    try {
      final list = await (widget.db.select(widget.db.categories)
            ..where((tbl) => tbl.userId.equals(widget.userId) & tbl.isDeleted.equals(false)))
          .get();
      setState(() {
        _categories = list;
        _isLoadingCategories = false;
        
        // Match default category if not set
        if (_selectedCategoryId == null && list.isNotEmpty) {
          final firstMatch = list.firstWhere(
            (c) => c.type == _type || c.type == 'both',
            orElse: () => list.first,
          );
          _selectedCategoryId = firstMatch.id;
        }
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  // ── SAVE TRANSACTION HANDLER ───────────────────────────────────────
  void _saveTransaction() async {
    if (!_formKey.currentState!.validate() || _selectedCategoryId == null) return;

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final merchant = _merchantController.text.trim().isEmpty ? null : _merchantController.text.trim();
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    try {
      if (widget.transactionToEdit == null) {
        // Create Transaction
        final id = _uuid.v4();
        await widget.db.into(widget.db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            userId: widget.userId,
            type: _type,
            amount: amount,
            currency: const drift.Value('INR'),
            categoryId: _selectedCategoryId!,
            date: _selectedDate,
            notes: drift.Value(notes),
            merchant: drift.Value(merchant),
            source: 'manual',
            confidence: 'high',
            status: 'confirmed',
            isRecurring: const drift.Value(false),
            isSynced: const drift.Value(false),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        // Edit Transaction
        final original = widget.transactionToEdit!;
        await widget.db.update(widget.db.transactions).replace(
          Transaction(
            id: original.id,
            userId: widget.userId,
            type: _type,
            amount: amount,
            currency: original.currency,
            categoryId: _selectedCategoryId!,
            date: _selectedDate,
            notes: notes,
            merchant: merchant,
            source: original.source,
            confidence: original.confidence,
            status: original.status,
            isRecurring: original.isRecurring,
            recurringId: original.recurringId,
            importBatchId: original.importBatchId,
            isSynced: false,
            isDeleted: false,
            createdAt: original.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving transaction: $e');
    }
  }

  // ── RENDER PICK DATE DIALOG ────────────────────────────────────────
  void _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 305)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.transactionToEdit != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Slide Bar Indicator
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Text(
              isEdit ? 'Edit Transaction' : 'New Transaction',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── TYPE TOGGLE CAPSULES ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _type = 'expense';
                        _loadCategories();
                      });
                    },
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _type == 'expense' ? theme.colorScheme.error : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Expense',
                          style: TextStyle(
                            color: _type == 'expense' ? Colors.white : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _type = 'income';
                        _loadCategories();
                      });
                    },
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _type == 'income' ? theme.primaryColor : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Income',
                          style: TextStyle(
                            color: _type == 'income' ? Colors.white : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── AMOUNT INPUT ──────────────────────────────────────────
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Enter transaction amount';
                final val = double.tryParse(value);
                if (val == null || val <= 0) return 'Enter a valid amount';
                return null;
              },
              decoration: const InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                labelText: 'Amount',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 16),

            // ── CATEGORY PICKER ───────────────────────────────────────
            _isLoadingCategories
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    onChanged: (val) => setState(() => _selectedCategoryId = val),
                    validator: (value) => value == null ? 'Select category' : null,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _categories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat.id,
                        child: Row(
                          children: [
                            Text(cat.icon, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(cat.name),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 16),

            // ── DATE SELECTOR ─────────────────────────────────────────
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('d MMMM yyyy').format(_selectedDate),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── MERCHANT / SOURCE ─────────────────────────────────────
            TextFormField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Merchant / Payee Name',
                prefixIcon: Icon(Icons.storefront_outlined),
                hintText: 'e.g. Swiggy, Uber, Rent',
              ),
            ),
            const SizedBox(height: 16),

            // ── NOTES ─────────────────────────────────────────────────
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined),
                hintText: 'Additional remarks...',
              ),
            ),
            const SizedBox(height: 24),

            // ── SAVE BUTTON ───────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saveTransaction,
                child: Text(isEdit ? 'Save Changes' : 'Record Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
