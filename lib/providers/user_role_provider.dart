import 'package:flutter/foundation.dart';

enum UserRole { student, instructor, unknown }

/// Tracks the currently authenticated user's role.
/// Populated by AuthWrapper after reading Firestore `users/{uid}.role`.
class UserRoleProvider extends ChangeNotifier {
  UserRole _role = UserRole.unknown;
  String? _fullName;
  String? _uid;
  bool _requiresEmailVerification = false;

  UserRole get role => _role;
  String? get fullName => _fullName;
  String? get uid => _uid;
  bool get requiresEmailVerification => _requiresEmailVerification;

  bool get isStudent => _role == UserRole.student;
  bool get isInstructor => _role == UserRole.instructor;

  void setUser({
    required String uid,
    required String fullName,
    required String role,
    bool requiresEmailVerification = false,
  }) {
    final newRole = role.toLowerCase() == 'instructor'
        ? UserRole.instructor
        : UserRole.student;
    if (_uid == uid &&
        _fullName == fullName &&
        _role == newRole &&
        _requiresEmailVerification == requiresEmailVerification) {
      return; // Deduplicate to avoid rebuild thrashing
    }

    _uid = uid;
    _fullName = fullName;
    _role = newRole;
    _requiresEmailVerification = requiresEmailVerification;
    notifyListeners();
  }

  void clear() {
    if (_role == UserRole.unknown && _uid == null && _fullName == null) return;
    _role = UserRole.unknown;
    _fullName = null;
    _uid = null;
    _requiresEmailVerification = false;
    notifyListeners();
  }
}
