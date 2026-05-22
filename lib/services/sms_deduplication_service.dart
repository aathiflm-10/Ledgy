import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

class SmsDeduplicationService {
  final AppDatabase _db;

  SmsDeduplicationService(this._db);

  // ── GENERATE FINGERPRINT ───────────────────────────────────────────
  String generateFingerprint({
    required double amount,
    required DateTime timestamp,
    required String type,
    required String uid,
  }) {
    // 5-minute time window bucket (Epoch time / 300,000 ms)
    final int timeBucket = timestamp.millisecondsSinceEpoch ~/ 300000;
    final String amountStr = amount.toStringAsFixed(2);
    
    final String input = '$amountStr|$timeBucket|$type|$uid';
    final digest = sha256.convert(utf8.encode(input));
    
    // Return first 16 characters of the hex string
    return digest.toString().substring(0, 16);
  }

  // ── DEDUPLICATION CHECK & LOG ──────────────────────────────────────
  /// Returns `true` if this SMS fingerprint is a duplicate.
  /// If NOT a duplicate, it registers the fingerprint in the database.
  Future<bool> checkAndRegister({
    required String fingerprint,
    required String transactionId,
    required String userId,
    required DateTime receivedAt,
  }) async {
    return await _db.transaction(() async {
      // 1. Check if fingerprint already exists
      final query = _db.select(_db.smsDedupeLog)
        ..where((tbl) => tbl.fingerprint.equals(fingerprint) & tbl.userId.equals(userId));
      
      final existing = await query.getSingleOrNull();

      if (existing != null) {
        // Increment duplicate count
        final updatedCount = existing.duplicateCount + 1;
        await _db.update(_db.smsDedupeLog).replace(
          SmsDedupeLogCompanion(
            fingerprint: Value(fingerprint),
            userId: Value(userId),
            transactionId: Value(existing.transactionId),
            firstSeenAt: Value(existing.firstSeenAt),
            duplicateCount: Value(updatedCount),
          ),
        );
        return true; // Yes, it is a duplicate
      }

      // 2. Not a duplicate, insert record in SmsDedupeLog
      await _db.into(_db.smsDedupeLog).insert(
        SmsDedupeLogCompanion.insert(
          fingerprint: fingerprint,
          userId: userId,
          transactionId: transactionId,
          firstSeenAt: receivedAt,
          duplicateCount: const Value(0),
        ),
      );

      return false; // Not a duplicate
    });
  }
}
