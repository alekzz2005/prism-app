import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}


/// Wraps Firebase Authentication and Firestore user document operations.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Email / Password ────────────────────────────────────────────────

  /// Registers a new Student account and writes their profile to `users/{uid}`.
  /// Role is always "Student" — Instructor accounts are provisioned by admin.
  Future<UserCredential> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _writeUserDoc(
        uid: cred.user!.uid,
        email: email,
        fullName: fullName,
        role: 'Student',
      );
      return cred;
    } catch (e) {
      throw AuthException(_handleAuthError(e));
    }
  }

  /// Signs in with email and password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw AuthException(_handleAuthError(e));
    }
  }

  // ── Google Sign-In ───────────────────────────────────────────────────

  /// Signs in with Google. Creates a Firestore user doc if first-time login.
  /// Google users default to "Student" role unless already set as Instructor.
  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthException('Google sign-in was cancelled.');

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await _auth.signInWithCredential(credential);
      final uid = cred.user!.uid;

      // Only create the user doc if it doesn't exist yet (first-time Google login)
      final existing = await _db.collection('users').doc(uid).get();
      if (!existing.exists) {
        await _writeUserDoc(
          uid: uid,
          email: cred.user!.email ?? '',
          fullName: cred.user!.displayName ?? 'Student',
          role: 'Student',
        );
      }

      return cred;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(_handleAuthError(e));
    }
  }

  // ── Shared ───────────────────────────────────────────────────────────

  /// Fetches the user role and full name from Firestore.
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> signOut() async {
    // Gracefully attempt Google sign-out; silently skip if not a Google user
    // or if Google Play Services are unavailable (e.g. Huawei devices)
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {
      // Google Play Services not available — safe to ignore
    }
    await _auth.signOut();
  }

  // ── Private ──────────────────────────────────────────────────────────

  Future<void> _writeUserDoc({
    required String uid,
    required String email,
    required String fullName,
    required String role,
  }) =>
      _db.collection('users').doc(uid).set({
        'uid': uid,
        'fullName': fullName,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': false,
      });

  String _handleAuthError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          return 'Incorrect email or password. Please try again.';
        case 'email-already-in-use':
          return 'An account already exists for this email.';
        case 'weak-password':
          return 'The password is too weak. Please use at least 6 characters.';
        case 'invalid-email':
          return 'The email address is badly formatted.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        default:
          return e.message ?? 'An unknown authentication error occurred.';
      }
    }
    return 'An unexpected error occurred. Please try again.';
  }
}
