import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  }

  /// Signs in with email and password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  // ── Google Sign-In ───────────────────────────────────────────────────

  /// Signs in with Google. Creates a Firestore user doc if first-time login.
  /// Google users default to "Student" role unless already set as Instructor.
  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled.');

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
  }

  // ── Shared ───────────────────────────────────────────────────────────

  /// Fetches the user role and full name from Firestore.
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
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
}
