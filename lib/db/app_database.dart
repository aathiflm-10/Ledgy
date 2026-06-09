import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connection/connection.dart' as conn;

part 'app_database.g.dart';

// ── TABLES ──────────────────────────────────────────────────────────

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get type => text()(); // 'expense'|'income'|'transfer'
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get categoryId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get merchant => text().nullable()();
  TextColumn get source => text()(); // 'manual'|'pdf'|'csv'|'sms'|'recurring'
  TextColumn get confidence => text()(); // 'high'|'medium'|'low'
  TextColumn get status => text()(); // 'confirmed'|'pending'|'rejected'
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurringId => text().nullable()();
  TextColumn get importBatchId => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
    {userId, date},
    {userId, categoryId},
    {userId, status},
    {userId, source},
  ];
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()(); // emoji
  TextColumn get color => text()(); // hex string
  TextColumn get type => text()(); // 'expense'|'income'|'both'
  TextColumn get keywords => text()(); // JSON array
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
  ];
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get categoryId => text()();
  IntColumn get month => integer()();
  IntColumn get year => integer()();
  RealColumn get limitAmount => real()();
  IntColumn get alertAtPercent => integer().withDefault(const Constant(80))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
    {userId, categoryId, month, year},
  ];
}

class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentAmount => real().withDefault(const Constant(0.0))();
  DateTimeColumn get deadline => dateTime().nullable()();
  TextColumn get icon => text()();
  TextColumn get color => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
  ];
}

class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text()();
  RealColumn get amount => real()();
  TextColumn get type => text()(); // 'expense'|'income'
  TextColumn get frequency => text()(); // 'daily'|'weekly'|'monthly'|'yearly'
  DateTimeColumn get nextDueDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get reminderEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastGeneratedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
    {userId, isActive},
  ];
}

class KeywordMaps extends Table {
  TextColumn get keyword => text()();
  TextColumn get userId => text()();
  TextColumn get categoryId => text()();
  RealColumn get confidence => real()();
  BoolColumn get userConfirmed => boolean()();
  IntColumn get usageCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {keyword, userId};
}

class RawSmsMessages extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get status => text()(); // 'pending'|'processed'|'duplicate'|'failed'
  TextColumn get parsedTransactionId => text().nullable()();
  TextColumn get failReason => text().nullable()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get indexes => [
    {userId},
    {userId, fingerprint},
  ];
}

class SmsDedupeLog extends Table {
  TextColumn get fingerprint => text()();
  TextColumn get userId => text()();
  TextColumn get transactionId => text()();
  DateTimeColumn get firstSeenAt => dateTime()();
  IntColumn get duplicateCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {fingerprint, userId};
}

// ── DATABASE ORM CLASS ───────────────────────────────────────────────

@DriftDatabase(tables: [
  Transactions,
  Categories,
  Budgets,
  SavingsGoals,
  RecurringRules,
  KeywordMaps,
  RawSmsMessages,
  SmsDedupeLog,
])
class AppDatabase extends _$AppDatabase {
  final String userId;

  AppDatabase(this.userId) : super(_openConnection(userId));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Proactively seed default categories upon first launch for this UID
      await seedDefaultCategories(userId);
    },
  );

  static QueryExecutor _openConnection(String uid) {
    return conn.openConnection(uid);
  }

  // ── SEEDING DEFAULT CATEGORIES ─────────────────────────────────────
  Future<void> seedDefaultCategories(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final seedKey = 'categoriesSeeded_$uid';
    final alreadySeeded = prefs.getBool(seedKey) ?? false;
    
    final defaultCategories = [
      {'id': 'cat_food', 'name': 'Food & Dining', 'icon': '🍴', 'color': '#F59E0B', 'type': 'expense', 'keywords': '["swiggy","zomato","pizza","restaurant","cafe","dunzo","blinkit","foodpanda"]'},
      {'id': 'cat_transport', 'name': 'Transport', 'icon': '🚗', 'color': '#3B82F6', 'type': 'expense', 'keywords': '["uber","ola","rapido","metro","bus","petrol","irctc","redbus","makemytrip"]'},
      {'id': 'cat_shopping', 'name': 'Shopping', 'icon': '🛍️', 'color': '#EC4899', 'type': 'expense', 'keywords': '["amazon","flipkart","myntra","ajio","meesho","nykaa","snapdeal"]'},
      {'id': 'cat_ent', 'name': 'Entertainment', 'icon': '🎬', 'color': '#8B5CF6', 'type': 'expense', 'keywords': '["netflix","hotstar","spotify","prime","bookmyshow","steam","youtube"]'},
      {'id': 'cat_utilities', 'name': 'Utilities', 'icon': '⚡', 'color': '#10B981', 'type': 'expense', 'keywords': '["electricity","water","gas","broadband","wifi","airtel","jio","bsnl","tata"]'},
      {'id': 'cat_housing', 'name': 'Housing', 'icon': '🏠', 'color': '#6366F1', 'type': 'expense', 'keywords': '["rent","maintenance","society","deposit","landlord"]'},
      {'id': 'cat_health', 'name': 'Health', 'icon': '❤️', 'color': '#F43F5E', 'type': 'expense', 'keywords': '["pharmacy","hospital","doctor","medicine","apollo","netmeds","1mg"]'},
      {'id': 'cat_edu', 'name': 'Education', 'icon': '📚', 'color': '#F97316', 'type': 'expense', 'keywords': '["school","college","tuition","udemy","coursera","fees"]'},
      {'id': 'cat_invest', 'name': 'Investment', 'icon': '📈', 'color': '#0EA5E9', 'type': 'expense', 'keywords': '["mutual fund","sip","zerodha","groww","fd","nps","stocks"]'},
      {'id': 'cat_salary', 'name': 'Salary', 'icon': '💰', 'color': '#22C55E', 'type': 'income', 'keywords': '["salary","credited","payroll","stipend","wages","bonus"]'},
      {'id': 'cat_gifts', 'name': 'Gifts & Cashbacks', 'icon': '🎁', 'color': '#D946EF', 'type': 'income', 'keywords': '["gift","cashback","refund","reward","friend","received"]'},
      {'id': 'cat_transfer', 'name': 'Transfer', 'icon': '🔁', 'color': '#94A3B8', 'type': 'both', 'keywords': '["transfer","neft","imps","rtgs","upi","gpay","phonepe"]'},
      {'id': 'cat_other', 'name': 'Other', 'icon': '📌', 'color': '#64748B', 'type': 'both', 'keywords': '[]'},
    ];

    if (alreadySeeded) {
      // Just ensure cat_gifts is present for existing users who already seeded
      await customStatement(
        'INSERT OR IGNORE INTO categories (id, user_id, name, icon, color, type, keywords, is_custom, is_synced, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0)',
        ['cat_gifts', uid, 'Gifts & Cashbacks', '🎁', '#D946EF', 'income', '["gift","cashback","refund","reward","friend","received"]']
      );
      return;
    }

    await transaction(() async {
      for (final cat in defaultCategories) {
        await customStatement(
          'INSERT OR IGNORE INTO categories (id, user_id, name, icon, color, type, keywords, is_custom, is_synced, is_deleted) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0)',
          [
            cat['id'],
            uid,
            cat['name'],
            cat['icon'],
            cat['color'],
            cat['type'],
            cat['keywords'],
          ],
        );
      }
    });

    await prefs.setBool(seedKey, true);
  }
}
