import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // ── INITIALIZE NOTIFICATIONS ───────────────────────────────────────
  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked with payload: ${details.payload}');
          // Navigation logic could be wired here
        },
      );
      debugPrint('Local Notifications initialized successfully.');
    } catch (e) {
      debugPrint('Failed to initialize local notifications (offline simulation fallback): $e');
    }
  }

  // ── REQUEST PERMISSIONS ────────────────────────────────────────────
  static Future<bool> requestPermissions() async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;

      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('Notification permission request skipped/failed: $e');
      return false;
    }
  }

  // ── SHOW NOTIFICATION ──────────────────────────────────────────────
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'ledgy_channel',
      'Ledgy Notifications',
      channelDescription: 'Notifications for automatic expense tracking',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await _notificationsPlugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('Skipped showing local notification: "$title" - $body due to environment: $e');
    }
  }

  // ── UTILITY HELPERS ────────────────────────────────────────────────
  static Future<void> showSmsDetected(double amount, String merchant) async {
    await showNotification(
      id: 101,
      title: '⚡ Transaction Detected',
      body: 'Spent ₹${amount.toStringAsFixed(0)} at $merchant. Tap to review.',
      payload: '/sms-review',
    );
  }

  static Future<void> showSmsDisabledAlert() async {
    await showNotification(
      id: 104,
      title: '⚡ Bank SMS Detected',
      body: 'Enable auto-detection to log transactions automatically.',
      payload: '/settings/sms',
    );
  }

  static Future<void> showBudgetAlert(String categoryName, int percent) async {
    await showNotification(
      id: 102,
      title: '⚠️ Budget Limit Reached',
      body: 'You have used $percent% of your monthly $categoryName budget!',
      payload: '/settings/budgets',
    );
  }

  static Future<void> showRecurringReminder(String name, double amount) async {
    await showNotification(
      id: 103,
      title: '🔁 Recurring Payment Due Tomorrow',
      body: '$name for ₹${amount.toStringAsFixed(0)} is scheduled for tomorrow.',
      payload: '/settings/recurring',
    );
  }
}
