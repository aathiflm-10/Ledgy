import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StreamProvider<SimulatedUser?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final currentUserProvider = Provider<SimulatedUser?>((ref) {
  // Try to read synchronous value if loaded, else fallback to current in-memory value
  return ref.watch(authStateProvider).value ?? ref.read(authServiceProvider).currentSimulatedUser;
});

final currentUidProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw Exception('Authentication required to access UID.');
  }
  return user.uid;
});
