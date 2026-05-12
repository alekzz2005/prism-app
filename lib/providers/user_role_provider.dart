import 'package:flutter/foundation.dart';

enum UserRole { student, instructor, unknown }

/// Tracks the currently authenticated user's role.
/// Populated by AuthWrapper after reading Firestore `users/{uid}.role`.
class UserRoleProvider extends ChangeNotifier {
  UserRole _role = UserRole.unknown;
  String? _fullName;
  String? _uid;

  UserRole get role => _role;
  String? get fullName => _fullName;
  String? get uid => _uid;

  bool get isStudent => _role == UserRole.student;
  bool get isInstructor => _role == UserRole.instructor;

  void setUser({
    required String uid,
    required String fullName,
    required String role,
  }) {
    _uid = uid;
    _fullName = fullName;
    _role = role.toLowerCase() == 'instructor'
        ? UserRole.instructor
        : UserRole.student;
    notifyListeners();
  }

  void clear() {
    _role = UserRole.unknown;
    _fullName = null;
    _uid = null;
    notifyListeners();
  }
}
