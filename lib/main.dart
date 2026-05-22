import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'providers/db_provider.dart';
import 'providers/auth_provider.dart';
import 'services/sms_service.dart';

// Global flag to track Firebase initialization success
bool isFirebaseAvailable = false;
late SharedPreferences globalPrefs;

void main() async {
  // 1. Auth Race Condition Fix & Native binding initialization
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Run Zoned Guarded for Global Crash Safety
  runZonedGuarded(() async {
    // 3. Initialize Shared Preferences
    try {
      globalPrefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences init error: $e');
    }

    // 4. Initialize Firebase resiliently
    try {
      await Firebase.initializeApp();
      isFirebaseAvailable = true;
      debugPrint('Firebase initialized successfully.');
    } catch (e) {
      debugPrint('Firebase initialization failed (simulated/offline mode enabled): $e');
      isFirebaseAvailable = false;
    }

    // 5. Global Flutter Error Handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Caught Flutter Error: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('Caught Async Platform Error: $error\n$stack');
      return true;
    };

    // 6. Start app
    runApp(
      const ProviderScope(
        child: LedgyApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught Zone Error: $error\n$stack');
  });
}

class LedgyApp extends ConsumerStatefulWidget {
  const LedgyApp({super.key});

  @override
  ConsumerState<LedgyApp> createState() => _LedgyAppState();
}

class _LedgyAppState extends ConsumerState<LedgyApp> {
  static const MethodChannel _smsChannel = MethodChannel('com.ledgy.financetracker/sms');

  @override
  void initState() {
    super.initState();
    _setupNativeSmsListener();
  }

  // ── HOOK UP THE METHOD CHANNEL TO CAPTURE NATIVE SMS INTERCEPTS ─────
  void _setupNativeSmsListener() {
    _smsChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onSmsReceived') {
        try {
          final args = call.arguments as Map<dynamic, dynamic>;
          final sender = args['sender'] as String;
          final body = args['body'] as String;
          final timestamp = args['timestamp'] as int;

          debugPrint('Dart SMS Listener received: sender=$sender, body=$body');

          final uid = ref.read(currentUidProvider);
          final db = ref.read(appDatabaseProvider);

          final smsService = SmsService(db);
          await smsService.processSms(
            sender: sender,
            body: body,
            timestampMillis: timestamp,
            uid: uid,
          );
        } catch (e) {
          debugPrint('Error handling incoming native SMS: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Ledgy Finance',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
