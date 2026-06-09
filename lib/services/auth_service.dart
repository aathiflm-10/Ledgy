import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../main.dart';

// Simulated User class to replicate Firebase User properties when offline
class SimulatedUser {
  final String uid;
  final String? email;
  final String? displayName;

  SimulatedUser({
    required this.uid,
    this.email,
    this.displayName,
  });
}

class AuthService {
  final FirebaseAuth? _auth = isFirebaseAvailable ? FirebaseAuth.instance : null;
  final FirebaseFirestore? _firestore = isFirebaseAvailable ? FirebaseFirestore.instance : null;

  // Local simulated stream controller for offline fallback
  static final StreamController<SimulatedUser?> _simulatedAuthStream = StreamController<SimulatedUser?>.broadcast();
  static SimulatedUser? _currentSimulatedUser;

  late final Stream<SimulatedUser?> _combinedAuthStream;

  AuthService() {
    if (!isFirebaseAvailable) {
      // Check if there was a saved simulated user session
      final savedUid = globalPrefs.getString('simulated_uid');
      if (savedUid != null) {
        _currentSimulatedUser = SimulatedUser(
          uid: savedUid,
          email: globalPrefs.getString('simulated_email') ?? 'offline@ledgy.com',
          displayName: globalPrefs.getString('simulated_name') ?? 'Offline User',
        );
      }
    }

    if (isFirebaseAvailable) {
      final controller = StreamController<SimulatedUser?>.broadcast();
      
      // Emit initial value asynchronously
      Timer.run(() {
        if (_auth!.currentUser != null) {
          controller.add(SimulatedUser(
            uid: _auth!.currentUser!.uid,
            email: _auth!.currentUser!.email,
            displayName: _auth!.currentUser!.displayName,
          ));
        } else {
          controller.add(null);
        }
      });

      _auth!.authStateChanges().listen((user) {
        if (user == null) {
          controller.add(null);
        } else {
          controller.add(SimulatedUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
          ));
        }
      });

      _simulatedAuthStream.stream.listen((user) {
        controller.add(user);
      });

      _combinedAuthStream = controller.stream;
    } else {
      _combinedAuthStream = _simulatedAuthStream.stream;
      if (_currentSimulatedUser != null) {
        Timer.run(() {
          _simulatedAuthStream.add(_currentSimulatedUser);
        });
      }
    }
  }

  Stream<SimulatedUser?> get authStateChanges => _combinedAuthStream;

  SimulatedUser? get currentSimulatedUser {
    if (isFirebaseAvailable) {
      final user = _auth!.currentUser;
      if (user == null) return null;
      return SimulatedUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
    } else {
      return _currentSimulatedUser;
    }
  }

  // ── SIGN UP ────────────────────────────────────────────────────────
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (isFirebaseAvailable) {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await credential.user!.updateDisplayName(name.trim());
      await credential.user!.reload();

      await _firestore!
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'name': name.trim(),
        'email': email.trim(),
        'currency': 'INR',
        'createdAt': FieldValue.serverTimestamp(),
        'hasOnboarded': false,
      });
    } else {
      // Simulated SignUp
      final uid = 'local_uid_${email.hashCode}';
      await globalPrefs.setString('simulated_uid', uid);
      await globalPrefs.setString('simulated_email', email);
      await globalPrefs.setString('simulated_name', name);
      await globalPrefs.setString('currency_$uid', 'INR');
      await globalPrefs.setBool('hasOnboarded_$uid', false);

      _currentSimulatedUser = SimulatedUser(uid: uid, email: email, displayName: name);
      _simulatedAuthStream.add(_currentSimulatedUser);
    }
  }

  // ── LOGIN ──────────────────────────────────────────────────────────
  Future<void> login({
    required String email,
    required String password,
  }) async {
    if (isFirebaseAvailable) {
      await _auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } else {
      // Simulated Login
      final uid = 'local_uid_${email.hashCode}';
      final savedName = globalPrefs.getString('simulated_name') ?? 'Offline User';
      await globalPrefs.setString('simulated_uid', uid);
      await globalPrefs.setString('simulated_email', email);

      _currentSimulatedUser = SimulatedUser(uid: uid, email: email, displayName: savedName);
      _simulatedAuthStream.add(_currentSimulatedUser);
    }
  }

  // ── GOOGLE SIGN IN ─────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    if (isFirebaseAvailable) {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) throw Exception('Google sign in cancelled');

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth!.signInWithCredential(credential);

      final doc = await _firestore!.collection('users').doc(result.user!.uid).get();
      if (!doc.exists) {
        await _firestore!.collection('users').doc(result.user!.uid).set({
          'name': result.user!.displayName ?? 'User',
          'email': result.user!.email ?? '',
          'currency': 'INR',
          'createdAt': FieldValue.serverTimestamp(),
          'hasOnboarded': false,
        });
      }
    } else {
      // Simulated Google login
      const email = 'google_user@gmail.com';
      final uid = 'local_uid_${email.hashCode}';
      await globalPrefs.setString('simulated_uid', uid);
      await globalPrefs.setString('simulated_email', email);
      await globalPrefs.setString('simulated_name', 'Google User');

      _currentSimulatedUser = SimulatedUser(uid: uid, email: email, displayName: 'Google User');
      _simulatedAuthStream.add(_currentSimulatedUser);
    }
  }

  // ── LOGOUT ─────────────────────────────────────────────────────────
  Future<void> logout() async {
    if (isFirebaseAvailable) {
      await _auth!.signOut();
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {}
    } else {
      await globalPrefs.remove('simulated_uid');
      await globalPrefs.remove('simulated_email');
      await globalPrefs.remove('simulated_name');

      _currentSimulatedUser = null;
      _simulatedAuthStream.add(null);
    }

    // Clear standard local preferences
    await globalPrefs.remove('selectedTheme');
    await globalPrefs.remove('currency');
  }

  // ── UPDATE DISPLAY NAME ────────────────────────────────────────────
  Future<void> updateDisplayName(String name) async {
    if (isFirebaseAvailable) {
      final user = _auth!.currentUser;
      if (user != null) {
        await user.updateDisplayName(name.trim());
        await user.reload();
        // Update in Firestore
        await _firestore!.collection('users').doc(user.uid).update({
          'name': name.trim(),
        });
        
        final updated = SimulatedUser(
          uid: user.uid,
          email: user.email,
          displayName: name.trim(),
        );
        _simulatedAuthStream.add(updated);
      }
    } else {
      final uid = currentSimulatedUser?.uid;
      if (uid != null) {
        await globalPrefs.setString('simulated_name', name.trim());
        _currentSimulatedUser = SimulatedUser(
          uid: uid,
          email: _currentSimulatedUser?.email ?? 'offline@ledgy.com',
          displayName: name.trim(),
        );
        _simulatedAuthStream.add(_currentSimulatedUser);
      }
    }
  }

  // ── PASSWORD RESET ─────────────────────────────────────────────────
  Future<void> sendPasswordReset(String email) async {
    if (isFirebaseAvailable) {
      await _auth!.sendPasswordResetEmail(email: email.trim());
    } else {
      debugPrint('Simulated password reset email sent to $email');
    }
  }

  // ── DELETE ACCOUNT ─────────────────────────────────────────────────
  Future<void> deleteAccount() async {
    final uid = currentSimulatedUser?.uid;
    if (uid == null) return;

    if (isFirebaseAvailable) {
      // Delete Firestore data
      await _deleteFirestoreUserData(uid);

      // Delete Auth
      await _auth!.currentUser!.delete();
    } else {
      await logout();
    }

    // Delete local DB file
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'ledgy_$uid.db'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _deleteFirestoreUserData(String uid) async {
    if (_firestore == null) return;
    final collections = [
      'transactions', 'categories', 'budgets',
      'goals', 'recurring', 'keyword_maps'
    ];
    for (final col in collections) {
      final snap = await _firestore!
          .collection('users').doc(uid).collection(col).get();
      final batch = _firestore!.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _firestore!.collection('users').doc(uid).delete();
  }
}
