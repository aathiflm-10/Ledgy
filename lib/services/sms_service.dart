import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';
import 'sms_parser.dart';
import 'sms_deduplication_service.dart';
import 'categorization_service.dart';
import '../main.dart';
import 'notification_service.dart';

class SmsService {
  final AppDatabase _db;
  final SmsDeduplicationService _dedupeService;
  final CategorizationService _categorizationService;
  final _uuid = const Uuid();

  SmsService(this._db)
      : _dedupeService = SmsDeduplicationService(_db),
        _categorizationService = CategorizationService(_db);

  // ── PROCESS LIVE SMS ───────────────────────────────────────────────
  Future<void> processSms({
    required String sender,
    required String body,
    required int timestampMillis,
    required String uid,
  }) async {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
    final rawSmsId = _uuid.v4();

    // 1. Run regex parser to detect transaction validity
    final parsed = SmsParser.parse(sender, body);
    
    // Calculate fingerprint regardless for raw logging
    final double amount = parsed?.amount ?? 0.0;
    final String type = parsed?.type ?? 'expense';
    
    final fingerprint = _dedupeService.generateFingerprint(
      amount: amount,
      timestamp: timestamp,
      type: type,
      uid: uid,
    );

    // Save RawSmsMessage first to ensure audits are intact
    await _db.into(_db.rawSmsMessages).insert(
      RawSmsMessagesCompanion.insert(
        id: rawSmsId,
        userId: uid,
        sender: sender,
        body: body,
        receivedAt: timestamp,
        status: 'pending',
        fingerprint: fingerprint,
        createdAt: DateTime.now(),
      ),
    );

    if (parsed == null) {
      // Update as failed parse (likely standard text, marketing or OTP missed by guards)
      await _db.update(_db.rawSmsMessages).replace(
        RawSmsMessagesCompanion(
          id: Value(rawSmsId),
          userId: Value(uid),
          sender: Value(sender),
          body: Value(body),
          receivedAt: Value(timestamp),
          status: const Value('failed'),
          failReason: const Value('Message did not match any known transaction pattern.'),
          fingerprint: Value(fingerprint),
          createdAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    // Check if auto-detection is enabled
    final bool detectionEnabled = globalPrefs.getBool('smsDetectionEnabled_$uid') ?? true;
    if (!detectionEnabled) {
      await NotificationService.showSmsDisabledAlert();
      await _db.update(_db.rawSmsMessages).replace(
        RawSmsMessagesCompanion(
          id: Value(rawSmsId),
          userId: Value(uid),
          sender: Value(sender),
          body: Value(body),
          receivedAt: Value(timestamp),
          status: const Value('failed'),
          failReason: const Value('SMS auto-detection is disabled in settings.'),
          fingerprint: Value(fingerprint),
          createdAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    // 2. Perform Deduplication check
    final txnId = _uuid.v4();
    final isDuplicate = await _dedupeService.checkAndRegister(
      fingerprint: fingerprint,
      transactionId: txnId,
      userId: uid,
      receivedAt: timestamp,
    );

    if (isDuplicate) {
      await _db.update(_db.rawSmsMessages).replace(
        RawSmsMessagesCompanion(
          id: Value(rawSmsId),
          userId: Value(uid),
          sender: Value(sender),
          body: Value(body),
          receivedAt: Value(timestamp),
          status: const Value('duplicate'),
          failReason: const Value('Duplicate transaction suppressed by deduplication engine.'),
          fingerprint: Value(fingerprint),
          createdAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    // 3. Auto-Categorize intelligently
    final categoryResult = await _categorizationService.classify(parsed.merchantHint, uid);

    final bool autoConfirm = globalPrefs.getBool('autoConfirmHighConfidence_$uid') ?? true;
    final bool isConfirmed = autoConfirm &&
        parsed.confidence == 'high' &&
        categoryResult.confidence == 'high';

    // 4. Auto-Create transaction in Drift
    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(
        TransactionsCompanion.insert(
          id: txnId,
          userId: uid,
          type: parsed.type,
          amount: parsed.amount,
          currency: const Value('INR'),
          categoryId: categoryResult.categoryId,
          date: timestamp,
          notes: Value('Automatically tracked from bank SMS (${parsed.bankName}).'),
          merchant: Value(parsed.merchantHint),
          source: 'sms',
          confidence: parsed.confidence == 'high' && categoryResult.confidence == 'high'
              ? 'high'
              : categoryResult.confidence,
          status: isConfirmed ? 'confirmed' : 'pending',
          isRecurring: const Value(false),
          isSynced: const Value(false),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 5. Update raw message logs
      await _db.update(_db.rawSmsMessages).replace(
        RawSmsMessagesCompanion(
          id: Value(rawSmsId),
          userId: Value(uid),
          sender: Value(sender),
          body: Value(body),
          receivedAt: Value(timestamp),
          status: const Value('processed'),
          parsedTransactionId: Value(txnId),
          fingerprint: Value(fingerprint),
          createdAt: Value(DateTime.now()),
        ),
      );
    });

    // 6. Trigger notifications
    if (isConfirmed) {
      await NotificationService.showNotification(
        id: 101,
        title: '⚡ Transaction Logged',
        body: 'Instantly logged ₹${parsed.amount.toStringAsFixed(0)} at ${parsed.merchantHint}.',
        payload: '/transactions',
      );
    } else {
      await NotificationService.showSmsDetected(parsed.amount, parsed.merchantHint);
    }

    debugPrint('Successfully processed SMS transaction: ₹${parsed.amount} at ${parsed.merchantHint}');
  }

  // ── HISTORICAL SMS SWEEP (LAST 90 DAYS) ────────────────────────────
  Future<int> importHistoricalSms(
    List<Map<String, dynamic>> smsList,
    String uid,
  ) async {
    int parsedCount = 0;

    // Process iteratively. We don't bulk-wrap in a single long transaction 
    // to avoid locking SQLite threads on large historical logs (e.g. 1000+ entries)
    for (final sms in smsList) {
      try {
        final sender = sms['sender'] as String? ?? '';
        final body = sms['body'] as String? ?? '';
        final timestampMillis = sms['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        if (sender.isEmpty || body.isEmpty) continue;

        // Process message using unified pipeline
        await processSms(
          sender: sender,
          body: body,
          timestampMillis: timestampMillis,
          uid: uid,
        );

        parsedCount++;
      } catch (e) {
        debugPrint('Error processing historical SMS record: $e');
      }
    }

    return parsedCount;
  }
}
