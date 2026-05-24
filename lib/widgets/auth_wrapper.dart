import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/user_role_provider.dart';
import '../services/auth_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/student/my_sessions_screen.dart';
import '../screens/instructor/instructor_dashboard_screen.dart';

/// Listens to Firebase Auth state changes and routes to the correct screen:
/// - Unauthenticated → LoginScreen
/// - Student role    → MySessionsScreen
/// - Instructor role → InstructorDashboardScreen
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Still waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;

        // Not logged in → show login
        if (user == null) {
          return const LoginScreen();
        }

        // Logged in → fetch role from Firestore
        return FutureBuilder<Map<String, dynamic>?>(
          future: authService.getUserData(user.uid),
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

            // No user doc found (e.g. Google sign-in on first launch before doc
            // is created) — default to Student
            final data = snap.data;
            if (data == null) {
              return const MySessionsScreen();
            }

            // Populate the UserRoleProvider
            final role = data['role'] as String? ?? 'Student';
            final fullName = data['fullName'] as String? ?? '';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<UserRoleProvider>().setUser(
                    uid: user.uid,
                    fullName: fullName,
                    role: role,
                  );
            });

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
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF003366), // Navy
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              SizedBox(height: 24),
              Text(
                'PRISM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'INITIALIZING...',
                style: TextStyle(
                  color: Color(0xFFA8C4E0), // Accent Blue
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
}
