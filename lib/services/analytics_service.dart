import 'package:drift/drift.dart';
import '../db/app_database.dart';

class SummaryData {
  final double totalIncome;
  final double totalExpense;
  final double netBalance;

  SummaryData({
    required this.totalIncome,
    required this.totalExpense,
    required this.netBalance,
  });
}

class CategoryTotal {
  final String categoryId;
  final String name;
  final String emoji;
  final String colorHex;
  final double total;
  final double percentage;

  CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.emoji,
    required this.colorHex,
    required this.total,
    required this.percentage,
  });
}

class MerchantTotal {
  final String merchant;
  final double total;

  MerchantTotal({
    required this.merchant,
    required this.total,
  });
}

class DailyTotal {
  final DateTime date;
  final double total;

  DailyTotal({
    required this.date,
    required this.total,
  });
}

class AnalyticsService {
  final AppDatabase _db;

  AnalyticsService(this._db);

  // ── GET SUMMARY ────────────────────────────────────────────────────
  Future<SummaryData> getSummary(String uid, DateTime from, DateTime to) async {
    final query = _db.select(_db.transactions)
      ..where((tbl) =>
          tbl.userId.equals(uid) &
          tbl.date.isBetweenValues(from, to) &
          tbl.isDeleted.equals(false) &
          tbl.status.equals('confirmed'));

    final txns = await query.get();

    double income = 0.0;
    double expense = 0.0;

    for (final txn in txns) {
      if (txn.type == 'income') {
        income += txn.amount;
      } else if (txn.type == 'expense') {
        expense += txn.amount;
      }
    }

    return SummaryData(
      totalIncome: income,
      totalExpense: expense,
      netBalance: income - expense,
    );
  }

  // ── GET CATEGORY TOTALS ─────────────────────────────────────────────
  Future<List<CategoryTotal>> getCategoryTotals(String uid, DateTime from, DateTime to) async {
    final txns = await (_db.select(_db.transactions)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.date.isBetweenValues(from, to) &
              tbl.isDeleted.equals(false) &
              tbl.status.equals('confirmed')))
        .get();

    final categories = await (_db.select(_db.categories)
          ..where((tbl) => tbl.userId.equals(uid)))
        .get();

    final Map<String, double> categorySum = {};
    double totalExpense = 0.0;

    for (final txn in txns) {
      if (txn.type != 'expense') continue;
      categorySum[txn.categoryId] = (categorySum[txn.categoryId] ?? 0.0) + txn.amount;
      totalExpense += txn.amount;
    }

    final List<CategoryTotal> result = [];
    categorySum.forEach((catId, sum) {
      final cat = categories.firstWhere(
        (c) => c.id == catId,
        orElse: () => Category(
          id: catId,
          userId: uid,
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

      result.add(CategoryTotal(
        categoryId: catId,
        name: cat.name,
        emoji: cat.icon,
        colorHex: cat.color,
        total: sum,
        percentage: totalExpense > 0 ? (sum / totalExpense) * 100 : 0.0,
      ));
    });

    // Sort descending by amount
    result.sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  // ── GET TOP MERCHANTS ──────────────────────────────────────────────
  Future<List<MerchantTotal>> getTopMerchants(String uid, DateTime from, DateTime to) async {
    final txns = await (_db.select(_db.transactions)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.date.isBetweenValues(from, to) &
              tbl.isDeleted.equals(false) &
              tbl.status.equals('confirmed') &
              tbl.type.equals('expense')))
        .get();

    final Map<String, double> merchantSum = {};
    for (final txn in txns) {
      final name = txn.merchant ?? 'Unknown Merchant';
      merchantSum[name] = (merchantSum[name] ?? 0.0) + txn.amount;
    }

    final List<MerchantTotal> result = merchantSum.entries
        .map((e) => MerchantTotal(merchant: e.key, total: e.value))
        .toList();

    result.sort((a, b) => b.total.compareTo(a.total));
    return result.take(5).toList();
  }

  // ── GET DAILY TOTALS ───────────────────────────────────────────────
  Future<List<DailyTotal>> getDailyTotals(String uid, DateTime from, DateTime to) async {
    final txns = await (_db.select(_db.transactions)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.date.isBetweenValues(from, to) &
              tbl.isDeleted.equals(false) &
              tbl.status.equals('confirmed') &
              tbl.type.equals('expense')))
        .get();

    final Map<DateTime, double> dailySum = {};
    for (final txn in txns) {
      final dateKey = DateTime(txn.date.year, txn.date.month, txn.date.day);
      dailySum[dateKey] = (dailySum[dateKey] ?? 0.0) + txn.amount;
    }

    final List<DailyTotal> result = dailySum.entries
        .map((e) => DailyTotal(date: e.key, total: e.value))
        .toList();

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  // ── GENERATE SMART INSIGHTS ────────────────────────────────────────
  Future<List<String>> generateInsights(String uid) async {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);

    // 1. Fetch current month expenses
    final thisMonthSummary = await getSummary(uid, thisMonthStart, now);
    // 2. Fetch last month expenses
    final lastMonthSummary = await getSummary(uid, lastMonthStart, lastMonthEnd);

    final List<String> insights = [];

    // Compare totals
    if (lastMonthSummary.totalExpense > 0) {
      final diff = thisMonthSummary.totalExpense - lastMonthSummary.totalExpense;
      final percent = (diff / lastMonthSummary.totalExpense * 100).abs();
      if (diff > 0 && percent > 15) {
        insights.add('⚠️ Spend Alert: You have spent ${percent.toStringAsFixed(0)}% more than last month at this stage.');
      } else if (diff < 0 && percent > 15) {
        insights.add('🎉 Great Job! Your expenses are ${percent.toStringAsFixed(0)}% lower than last month.');
      }
    }

    // Check single largest expenses
    final largestTxn = await (_db.select(_db.transactions)
          ..where((tbl) =>
              tbl.userId.equals(uid) &
              tbl.isDeleted.equals(false) &
              tbl.type.equals('expense') &
              tbl.status.equals('confirmed'))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.amount)])
          ..limit(1))
        .getSingleOrNull();

    if (largestTxn != null && largestTxn.amount > 5000) {
      insights.add('💡 Large Transaction: Your single largest expense was ₹${largestTxn.amount.toStringAsFixed(0)} at ${largestTxn.merchant ?? 'Merchant'}.');
    }

    // Check high category expenses
    final catTotals = await getCategoryTotals(uid, thisMonthStart, now);
    if (catTotals.isNotEmpty) {
      final topCat = catTotals.first;
      if (topCat.percentage > 35) {
        insights.add('📊 Category Focus: Spending in "${topCat.emoji} ${topCat.name}" is making up ${topCat.percentage.toStringAsFixed(0)}% of your monthly outflows.');
      }
    }

    if (insights.isEmpty) {
      insights.add('✨ Cashflow is looking healthy! Keep tracking automatically with bank SMS.');
    }

    return insights;
  }
}
