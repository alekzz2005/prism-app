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

  /// Validates standard email address format (e.g., student@cit.edu, user@gmail.com, etc.).
  static bool isValidEmail(String email) {
    final clean = email.trim().toLowerCase();
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(clean);
  }

  /// Registers a new Student account and writes their profile to `users/{uid}`.
  /// Role is always "Student" — Instructor accounts are provisioned by admin.
  Future<UserCredential> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // Validate email format
    if (!isValidEmail(cleanEmail)) {
      throw AuthException('Incorrect email format. Please enter a valid email address.');
    }

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      // Write Firestore user profile document first
      await _writeUserDoc(
        uid: cred.user!.uid,
        email: cleanEmail,
        fullName: fullName,
        role: 'Student',
        requiresEmailVerification: true,
      );

      // Send Firebase verification email if supported
      try {
        await cred.user?.sendEmailVerification();
      } catch (_) {}

      return cred;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(_handleAuthError(e));
    }
  }

  /// Signs in with email and password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      return await _auth.signInWithEmailAndPassword(email: cleanEmail, password: password);
    } catch (e) {
      if (e is AuthException) rethrow;
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
      final email = (cred.user!.email ?? '').toLowerCase().trim();

      // Only create the user doc if it doesn't exist yet (first-time Google login)
      final userRef = _db.collection('users').doc(uid);
      final existing = await userRef.get();
      if (!existing.exists) {
        await _writeUserDoc(
          uid: uid,
          email: email,
          fullName: cred.user!.displayName ?? 'Student',
          role: 'Student',
          authProvider: 'google',
          hasPassword: false,
        );
      } else {
        final data = existing.data() ?? {};
        final hasConfirmedPassword = data['hasPassword'] == true;
        // Google OAuth confirms account ownership; mark verified in Firestore
        await userRef.set({
          'emailVerified': true,
          'requiresEmailVerification': false,
          if (!hasConfirmedPassword) 'authProvider': 'google',
          if (!hasConfirmedPassword) 'hasPassword': false,
        }, SetOptions(merge: true));
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
    bool requiresEmailVerification = false,
    String authProvider = 'password',
    bool hasPassword = true,
  }) =>
      _db.collection('users').doc(uid).set({
        'uid': uid,
        'fullName': fullName,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': false,
        'authProvider': authProvider,
        'hasPassword': hasPassword,
        if (requiresEmailVerification) 'requiresEmailVerification': true,
      }, SetOptions(merge: true));

  String _handleAuthError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
          return 'Incorrect email or password. Please try again.';
        case 'email-already-in-use':
          return 'An account already exists for this email address.';
        case 'weak-password':
          return 'Password is too weak. Please use at least 8 characters with uppercase, lowercase, and a number or symbol.';
        case 'invalid-email':
          return 'Incorrect email format. Please enter a valid email address.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact your instructor or administrator.';
        case 'too-many-requests':
          return 'Too many failed login attempts. Please try again in a few moments.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection and try again.';
        case 'requires-recent-login':
          return 'For security, please sign in again before performing this action.';
        default:
          return e.message ?? 'An unknown authentication error occurred.';
      }
    }
    return 'An unexpected error occurred. Please try again.';
  }
}
