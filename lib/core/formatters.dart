import 'package:intl/intl.dart';

class Formatters {
  static String formatCurrency(double amount, {String symbol = '₹'}) {
    // Determine the locale based on symbol for better formatting
    String locale = 'en_US';
    if (symbol == '₹') {
      locale = 'en_IN';
    } else if (symbol == '€') {
      locale = 'de_DE';
    } else if (symbol == '£') {
      locale = 'en_GB';
    }

    try {
      final formatter = NumberFormat.currency(
        locale: locale,
        symbol: symbol,
        decimalDigits: amount % 1 == 0 ? 0 : 2,
      );
      return formatter.format(amount);
    } catch (e) {
      return '$symbol${amount.toStringAsFixed(2)}';
    }
  }

  static String formatLongDate(DateTime date) {
    return DateFormat('d MMM yyyy').format(date.toLocal());
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('d MMM').format(date.toLocal());
  }

  static String formatTimestamp(DateTime date) {
    return DateFormat('d MMM, h:mm a').format(date.toLocal());
  }

  static String formatMonthYear(int month, int year) {
    final date = DateTime(year, month);
    return DateFormat('MMMM yyyy').format(date);
  }
}
