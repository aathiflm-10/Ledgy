import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';

class CategorizationResult {
  final String categoryId;
  final String confidence; // 'high' | 'medium' | 'low'

  CategorizationResult({
    required this.categoryId,
    required this.confidence,
  });
}

class CategorizationService {
  final AppDatabase _db;

  CategorizationService(this._db);

  // Stop words to ignore during learning
  static const Set<String> _stopWords = {
    'the', 'and', 'for', 'you', 'with', 'from', 'your', 'this', 'that',
    'paid', 'sent', 'received', 'credited', 'debited', 'towards', 'info', 'bank',
    'acct', 'account', 'using', 'card', 'txn', 'transaction', 'transfer'
  };

  // ── CLASSIFY DESCRIPTION ───────────────────────────────────────────
  Future<CategorizationResult> classify(String description, String uid) async {
    final normalized = description.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');

    // 1. Check for salary patterns (large income around month start/end)
    final now = DateTime.now();
    final day = now.day;
    if ((day <= 5 || day >= 26) && 
        (normalized.contains('salary') || normalized.contains('credited') || normalized.contains('payroll'))) {
      return CategorizationResult(
        categoryId: 'cat_salary',
        confidence: 'high',
      );
    }

    // 2. Query user-specific learned KeywordMaps from DB
    final savedKeywords = await (_db.select(_db.keywordMaps)
          ..where((tbl) => tbl.userId.equals(uid))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.usageCount)]))
        .get();

    for (final kwMap in savedKeywords) {
      if (normalized.contains(kwMap.keyword)) {
        String conf = 'medium';
        if (kwMap.userConfirmed) conf = 'high';
        else if (kwMap.confidence > 0.8) conf = 'high';
        else if (kwMap.confidence < 0.5) conf = 'low';

        return CategorizationResult(
          categoryId: kwMap.categoryId,
          confidence: conf,
        );
      }
    }

    // 3. Fallback: Search default categories' pre-seeded keywords
    final categories = await (_db.select(_db.categories)
          ..where((tbl) => tbl.userId.equals(uid)))
        .get();

    for (final cat in categories) {
      if (cat.keywords.isEmpty) continue;
      try {
        final List<dynamic> kwList = jsonDecode(cat.keywords);
        for (final dynamic kw in kwList) {
          if (kw is String && normalized.contains(kw.toLowerCase())) {
            return CategorizationResult(
              categoryId: cat.id,
              confidence: 'medium',
            );
          }
        }
      } catch (e) {
        debugPrint('Error parsing keywords for category ${cat.name}: $e');
      }
    }

    // 4. Default: Category Other with low confidence
    return CategorizationResult(
      categoryId: 'cat_other',
      confidence: 'low',
    );
  }

  // ── LEARN FROM CORRECTION ──────────────────────────────────────────
  Future<void> learnCorrection(String description, String newCategoryId, String uid) async {
    // Normalize and tokenize
    final normalized = description.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');
    final tokens = normalized.split(' ').map((t) => t.trim()).where((t) => t.length > 3 && !_stopWords.contains(t)).toList();

    if (tokens.isEmpty) return;

    await _db.transaction(() async {
      for (final token in tokens) {
        // Upsert into KeywordMaps
        final query = _db.select(_db.keywordMaps)
          ..where((tbl) => tbl.keyword.equals(token) & tbl.userId.equals(uid));
        
        final existing = await query.getSingleOrNull();

        if (existing != null) {
          // Increment count and confirm
          await _db.update(_db.keywordMaps).replace(
            existing.copyWith(
              categoryId: newCategoryId,
              confidence: 1.0,
              userConfirmed: true,
              usageCount: existing.usageCount + 1,
            ),
          );
        } else {
          // New map entry
          await _db.into(_db.keywordMaps).insert(
            KeywordMapsCompanion.insert(
              keyword: token,
              userId: uid,
              categoryId: newCategoryId,
              confidence: 1.0,
              userConfirmed: true,
              usageCount: const Value(1),
            ),
          );
        }
      }
    });

    // Fire-and-forget Firestore learning upload in Phase 13 sync routines
  }
}
