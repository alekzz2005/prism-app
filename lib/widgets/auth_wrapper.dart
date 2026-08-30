import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/user_role_provider.dart';
import '../services/auth_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/student/my_sessions_screen.dart';
import '../screens/instructor/instructor_dashboard_screen.dart';

/// Listens to Firebase Auth state changes and routes to the correct screen:
/// - Unauthenticated → LoginScreen
/// - Email not verified (new signups only) → EmailVerificationScreen
/// - Student role    → MySessionsScreen
/// - Instructor role → InstructorDashboardScreen
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  String? _fetchedUid;
  Future<Map<String, dynamic>?>? _userDocFuture;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      initialData: FirebaseAuth.instance.currentUser,
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // Still waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;

        // Not logged in → show login
        if (user == null) {
          _fetchedUid = null;
          _userDocFuture = null;
          return const LoginScreen();
        }

        // Check if role is already resolved in UserRoleProvider
        final userRole = context.watch<UserRoleProvider>();
        if (userRole.uid == user.uid && userRole.role != UserRole.unknown) {
          final isPasswordUser = user.providerData.any((p) => p.providerId == 'password');
          if (userRole.isStudent && isPasswordUser && userRole.requiresEmailVerification && !user.emailVerified) {
            return const EmailVerificationScreen();
          }
          if (userRole.isInstructor) {
            return const InstructorDashboardScreen();
          }
          return const MySessionsScreen();
        }

        // Memoize future so it only executes once per user UID
        if (_fetchedUid != user.uid || _userDocFuture == null) {
          _fetchedUid = user.uid;
          _userDocFuture = _authService.getUserData(user.uid);
        }

        // Fetch user data from Firestore
        return FutureBuilder<Map<String, dynamic>?>(
          future: _userDocFuture,
          builder: (context, snap) {
            // ── Error (e.g. Firestore PERMISSION_DENIED before rules are set) ──
            // Fall back to Student home so the app doesn't hang forever.
            if (snap.hasError) {
              debugPrint(
                  '[AuthWrapper] Firestore error — defaulting to Student: ${snap.error}');
              return const MySessionsScreen();
            }

            // Still loading Firestore doc
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final data = snap.data;
            final role = data?['role'] as String? ?? 'Student';
            final fullName = data?['fullName'] as String? ?? '';
            final requiresVerification = data?['requiresEmailVerification'] == true;

            // Populate the UserRoleProvider
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.read<UserRoleProvider>().setUser(
                      uid: user.uid,
                      fullName: fullName,
                      role: role,
                      requiresEmailVerification: requiresVerification,
                    );
              }
            });

            // Only gate new student signups that explicitly have requiresEmailVerification == true
            final isPasswordUser = user.providerData.any((p) => p.providerId == 'password');
            if (role == 'Student' && isPasswordUser && requiresVerification && !user.emailVerified) {
              return const EmailVerificationScreen();
            }

            if (role == 'Instructor') {
              return const InstructorDashboardScreen();
            }
            return const MySessionsScreen();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF003366), // Navy
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PRISM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'INITIALIZING...',
                style: TextStyle(
                  color: Color(0xFFA8C4E0), // Accent Blue
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      );
}
