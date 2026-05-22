import 'package:flutter/foundation.dart';

class ParsedSms {
  final double amount;
  final String type; // 'expense' | 'income'
  final String merchantHint;
  final String bankName;
  final String confidence; // 'high' | 'medium' | 'low'

  ParsedSms({
    required this.amount,
    required this.type,
    required this.merchantHint,
    required this.bankName,
    required this.confidence,
  });
}

class SmsParser {
  // ── OTP & MARKETING GUARDS ─────────────────────────────────────────
  static bool shouldIgnore(String body) {
    final normalized = body.toLowerCase();
    
    // OTP / Verification Code Guard
    if (normalized.contains('otp') ||
        normalized.contains('one time') ||
        normalized.contains('verification code') ||
        normalized.contains('secure code') ||
        normalized.contains('security code')) {
      return true;
    }

    // Marketing Guard
    if (normalized.contains('offer') ||
        normalized.contains('cashback') ||
        normalized.contains('reward points') ||
        normalized.contains('pre-approved') ||
        normalized.contains('congratulations') ||
        normalized.contains('apply now') ||
        normalized.contains('discount')) {
      return true;
    }

    return false;
  }

  // ── CORE REGEX ENGINE ──────────────────────────────────────────────
  static ParsedSms? parse(String sender, String body) {
    if (shouldIgnore(body)) return null;

    final normalizedBody = body.toLowerCase();
    final normalizedSender = sender.toUpperCase();

    // Determine bank name from sender
    String bankName = _detectBank(normalizedSender, normalizedBody);

    // 1. Canara Bank Pattern
    final canaraReg = RegExp(r'amt[:\s]+rs\.?\s*([\d,]+\.?\d*)\s*(?:debited|credited)', caseSensitive: false);
    var match = canaraReg.firstMatch(body);
    if (match != null) {
      final amount = _cleanAmount(match.group(1));
      final type = normalizedBody.contains('credited') ? 'income' : 'expense';
      return ParsedSms(
        amount: amount,
        type: type,
        merchantHint: _extractMerchant(body, type),
        bankName: bankName.isEmpty ? 'Canara Bank' : bankName,
        confidence: 'high',
      );
    }

    // 2. HDFC Pattern
    final hdfcReg = RegExp(r'rs\.?\s*([\d,]+\.?\d*)\s*(debited|credited)\s+from\s+a\/c', caseSensitive: false);
    match = hdfcReg.firstMatch(body);
    if (match != null) {
      final amount = _cleanAmount(match.group(1));
      final type = match.group(2)!.toLowerCase() == 'credited' ? 'income' : 'expense';
      return ParsedSms(
        amount: amount,
        type: type,
        merchantHint: _extractMerchant(body, type),
        bankName: bankName.isEmpty ? 'HDFC Bank' : bankName,
        confidence: 'high',
      );
    }

    // 3. ICICI Pattern
    final iciciReg = RegExp(r'(?:debited|credited)\s+rs\.?\s*([\d,]+\.?\d*)', caseSensitive: false);
    match = iciciReg.firstMatch(body);
    if (match != null) {
      final amount = _cleanAmount(match.group(1));
      final type = normalizedBody.contains('credited') ? 'income' : 'expense';
      return ParsedSms(
        amount: amount,
        type: type,
        merchantHint: _extractMerchant(body, type),
        bankName: bankName.isEmpty ? 'ICICI Bank' : bankName,
        confidence: 'high',
      );
    }

    // 4. Generic Debit Pattern
    if (normalizedBody.contains('debit') || normalizedBody.contains('debited') || normalizedBody.contains('sent to') || normalizedBody.contains('paid to')) {
      final genericDebit = RegExp(r'(?:inr|rs\.?|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
      match = genericDebit.firstMatch(body);
      if (match != null) {
        final amount = _cleanAmount(match.group(1));
        return ParsedSms(
          amount: amount,
          type: 'expense',
          merchantHint: _extractMerchant(body, 'expense'),
          bankName: bankName.isEmpty ? 'Bank' : bankName,
          confidence: 'medium',
        );
      }
    }

    // 5. Generic Credit Pattern
    if (normalizedBody.contains('credit') || normalizedBody.contains('credited') || normalizedBody.contains('received from') || normalizedBody.contains('refunded')) {
      final genericCredit = RegExp(r'(?:inr|rs\.?|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
      match = genericCredit.firstMatch(body);
      if (match != null) {
        final amount = _cleanAmount(match.group(1));
        return ParsedSms(
          amount: amount,
          type: 'income',
          merchantHint: _extractMerchant(body, 'income'),
          bankName: bankName.isEmpty ? 'Bank' : bankName,
          confidence: 'medium',
        );
      }
    }

    // 6. Minimal Fallback Pattern
    final fallbackReg = RegExp(r'(?:inr|rs\.?|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
    match = fallbackReg.firstMatch(body);
    if (match != null) {
      final amount = _cleanAmount(match.group(1));
      final type = normalizedBody.contains('received') || normalizedBody.contains('refund') ? 'income' : 'expense';
      return ParsedSms(
        amount: amount,
        type: type,
        merchantHint: _extractMerchant(body, type),
        bankName: bankName.isEmpty ? 'Unknown Bank' : bankName,
        confidence: 'low',
      );
    }

    return null;
  }

  // ── HELPER UTILITIES ───────────────────────────────────────────────
  static double _cleanAmount(String? raw) {
    if (raw == null) return 0.0;
    // Remove commas and clean spaces
    final cleaned = raw.replaceAll(',', '').replaceAll(' ', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  static String _detectBank(String sender, String body) {
    final senderUpper = sender.toUpperCase();
    if (senderUpper.contains('CANBNK') || senderUpper.contains('CANBK')) return 'Canara Bank';
    if (senderUpper.contains('HDFCBK') || senderUpper.contains('HDFC')) return 'HDFC Bank';
    if (senderUpper.contains('ICICIB') || senderUpper.contains('ICICI')) return 'ICICI Bank';
    if (senderUpper.contains('SBIMSG') || senderUpper.contains('SBI')) return 'SBI';
    if (senderUpper.contains('AXISBK') || senderUpper.contains('AXIS')) return 'Axis Bank';
    if (senderUpper.contains('KOTAKB') || senderUpper.contains('KOTAK')) return 'Kotak Bank';
    if (senderUpper.contains('PAYTMB') || senderUpper.contains('PAYTM')) return 'Paytm Bank';
    
    // Scan body text if sender is generic
    final bodyLower = body.toLowerCase();
    if (bodyLower.contains('hdfc')) return 'HDFC Bank';
    if (bodyLower.contains('icici')) return 'ICICI Bank';
    if (bodyLower.contains('sbi')) return 'SBI';
    if (bodyLower.contains('canara')) return 'Canara Bank';
    if (bodyLower.contains('axis')) return 'Axis Bank';

    return 'Bank';
  }

  static String _extractMerchant(String body, String type) {
    final normalized = body.toLowerCase();
    
    // Look for merchant keywords like "at", "to", "info", "towards"
    final regexes = [
      RegExp(r'(?:spent\s+at|sent\s+to|paid\s+to|at|towards)\s+([a-zA-Z0-9\s\.\*\-\_\&]+?)(?:\s+using|\s+on|\s+from|\s+ref|\s+upi|\.|\,|$)', caseSensitive: false),
      RegExp(r'info\*\s*([a-zA-Z0-9\s\.\*\-\_\&]+?)(?:\s+on|\.|$)', caseSensitive: false),
    ];

    for (final reg in regexes) {
      final match = reg.firstMatch(body);
      if (match != null) {
        final rawMerchant = match.group(1)!.trim();
        if (rawMerchant.isNotEmpty && rawMerchant.length < 30) {
          return _cleanMerchantName(rawMerchant);
        }
      }
    }

    // Default fallbacks based on type
    return type == 'income' ? 'Income Source' : 'Merchant';
  }

  static String _cleanMerchantName(String name) {
    // Remove extra trailing/leading junk like transaction codes, stars, numbers
    var cleaned = name
        .replaceAll(RegExp(r'\*+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Capitalize first letters of words
    if (cleaned.isEmpty) return 'Merchant';
    
    try {
      return cleaned.split(' ').map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    } catch (_) {
      return cleaned;
    }
  }
}
