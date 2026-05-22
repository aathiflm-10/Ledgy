import 'package:drift/drift.dart';
import '../app_database.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase> with _$TransactionsDaoMixin {
  TransactionsDao(AppDatabase db) : super(db);

  Stream<List<Transaction>> watchAll(String userId) {
    return (select(transactions)
          ..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Future<List<Transaction>> getByMonth(String userId, int month, int year) {
    return (select(transactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.isDeleted.equals(false) &
              t.date.year.equals(year) &
              t.date.month.equals(month)))
        .get();
  }

  Future<Transaction?> getById(String id, String userId) {
    return (select(transactions)
          ..where((t) => t.id.equals(id) & t.userId.equals(userId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> insertTransaction(Transaction txn) =>
      into(transactions).insert(txn);

  Future<void> updateTransaction(Transaction txn) =>
      update(transactions).replace(txn);

  Future<void> softDelete(String id, String userId) {
    return (update(transactions)
          ..where((t) => t.id.equals(id) & t.userId.equals(userId)))
        .write(TransactionsCompanion(
          isDeleted: const Value(true),
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ));
  }
}
