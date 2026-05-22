import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'auth_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  // Watches the current logged-in user state
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw Exception('No authenticated user found for database scope.');
  }

  final db = AppDatabase(user.uid);

  // CRITICAL: Close the database connection when the user changes or logs out
  ref.onDispose(() {
    db.close();
  });

  return db;
});
