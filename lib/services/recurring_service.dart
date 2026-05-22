import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';

class RecurringService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  RecurringService(this._db);

  // ── CHECK AND GENERATE DUE RECURRING TRANSACTIONS ──────────────────
  Future<int> checkAndGenerateDueTransactions(String uid) async {
    final today = DateTime.now().toUtc();
    int generatedCount = 0;

    // 1. Fetch active recurring rules where nextDueDate <= today
    final rules = await (_db.select(_db.recurringRules)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.isActive.equals(true) &
              tbl.nextDueDate.isSmallerOrEqualValue(today) &
              tbl.isDeleted.equals(false)))
        .get();

    if (rules.isEmpty) return 0;

    // Process inside db transaction
    await _db.transaction(() async {
      for (final rule in rules) {
        // Prevent duplicate generation for same due cycle by double checking timestamps
        if (rule.lastGeneratedAt != null &&
            _isSameCycle(rule.lastGeneratedAt!, rule.nextDueDate, rule.frequency)) {
          continue;
        }

        final txnId = _uuid.v4();

        // 2. Insert transaction
        await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: txnId,
            userId: uid,
            type: rule.type,
            amount: rule.amount,
            currency: const Value('INR'),
            categoryId: rule.categoryId,
            date: rule.nextDueDate,
            notes: Value(rule.notes ?? 'Automatically generated recurring transaction.'),
            merchant: Value(rule.name),
            source: 'recurring',
            confidence: 'high',
            status: 'confirmed',
            isRecurring: const Value(true),
            recurringId: Value(rule.id),
            isSynced: const Value(false),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        // 3. Calculate next due date
        final nextDue = _calculateNextDueDate(rule.nextDueDate, rule.frequency);
        
        // 4. Check end date bounds
        bool stillActive = true;
        if (rule.endDate != null && nextDue.isAfter(rule.endDate!)) {
          stillActive = false;
        }

        // 5. Update RecurringRule in database
        await _db.update(_db.recurringRules).replace(
          RecurringRule(
            id: rule.id,
            userId: uid,
            name: rule.name,
            categoryId: rule.categoryId,
            amount: rule.amount,
            type: rule.type,
            frequency: rule.frequency,
            nextDueDate: nextDue,
            isActive: stillActive,
            notes: rule.notes,
            endDate: rule.endDate,
            reminderEnabled: rule.reminderEnabled,
            isSynced: false,
            isDeleted: false,
            lastGeneratedAt: DateTime.now().toUtc(),
          ),
        );

        generatedCount++;
      }
    });

    return generatedCount;
  }

  // ── RECURRING CYCLE HELPER ─────────────────────────────────────────
  bool _isSameCycle(DateTime lastGenerated, DateTime nextDue, String frequency) {
    if (frequency == 'daily') {
      return lastGenerated.year == nextDue.year &&
          lastGenerated.month == nextDue.month &&
          lastGenerated.day == nextDue.day;
    } else if (frequency == 'weekly') {
      final diff = lastGenerated.difference(nextDue).inDays.abs();
      return diff < 7;
    } else if (frequency == 'monthly') {
      return lastGenerated.year == nextDue.year && lastGenerated.month == nextDue.month;
    } else if (frequency == 'yearly') {
      return lastGenerated.year == nextDue.year;
    }
    return false;
  }

  DateTime _calculateNextDueDate(DateTime current, String frequency) {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return current.add(const Duration(days: 1));
      case 'weekly':
        return current.add(const Duration(days: 7));
      case 'monthly':
        // Safe month increment handling year roll
        int nextMonth = current.month + 1;
        int nextYear = current.year;
        if (nextMonth > 12) {
          nextMonth = 1;
          nextYear += 1;
        }
        // Retain original day if within bounds, else use end of month
        final lastDayOfNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
        int targetDay = current.day;
        if (targetDay > lastDayOfNextMonth) {
          targetDay = lastDayOfNextMonth;
        }
        return DateTime(nextYear, nextMonth, targetDay, current.hour, current.minute);
      case 'yearly':
        return DateTime(current.year + 1, current.month, current.day, current.hour, current.minute);
      default:
        return current.add(const Duration(days: 30));
    }
  }
}
