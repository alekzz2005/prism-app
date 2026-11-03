/// Pure Dart security policy evaluator mirroring `firestore.rules`.
///
/// Used for client-side defensive validation and deterministic unit testing
/// of PRISM's authorization model (Task 2: Role Escalation Prevention and
/// Task 3: Private Instructor Note Protection).
class FirestoreAuthContext {
  final String uid;
  final String? email;
  final Map<String, dynamic> tokenClaims;

  const FirestoreAuthContext({
    required this.uid,
    this.email,
    this.tokenClaims = const {},
  });

  bool get hasInstructorClaim =>
      tokenClaims['role'] == 'Instructor' ||
      tokenClaims['instructor'] == true;
}

class FirestoreSecurityPolicy {
  static const Set<String> allowedUserUpdateKeys = {
    'fullName',
    'email',
    'emailVerified',
    'requiresEmailVerification',
    'authProvider',
    'hasPassword',
  };

  static const Set<String> allowedStudentPracticeUpdateKeys = {
    'aiFeedbackText',
    'aiFeedbackOriginal',
    'aiValidationStatus',
    'aiValidationNotes',
  };

  /// Mirrors `isInstructor()` in `firestore.rules`.
  static bool isInstructor({
    required FirestoreAuthContext? auth,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    if (auth == null) return false;
    if (auth.hasInstructorClaim) return true;
    final userDoc = usersCollection[auth.uid];
    return userDoc != null && userDoc['role'] == 'Instructor';
  }

  /// Mirrors `hasNoPublicInstructorNote(data)` in `firestore.rules`.
  static bool hasNoPublicInstructorNote(Map<String, dynamic> data) {
    return !data.containsKey('instructorNote') || data['instructorNote'] == '';
  }

  /// Computes the set of keys that differ between [before] and [after],
  /// matching Firestore's `request.resource.data.diff(resource.data).affectedKeys()`.
  static Set<String> diffKeys(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final affected = <String>{};
    final allKeys = <String>{...before.keys, ...after.keys};
    for (final k in allKeys) {
      if (!before.containsKey(k) || !after.containsKey(k)) {
        affected.add(k);
      } else if (before[k] != after[k]) {
        affected.add(k);
      }
    }
    return affected;
  }

  // ── /users/{uid} ──────────────────────────────────────────────────────────

  static bool canReadUser({
    required FirestoreAuthContext? auth,
    required String targetUid,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    if (auth == null) return false;
    return auth.uid == targetUid ||
        isInstructor(auth: auth, usersCollection: usersCollection);
  }

  static bool canCreateUser({
    required FirestoreAuthContext? auth,
    required String targetUid,
    required Map<String, dynamic> newData,
  }) {
    if (auth == null) return false;
    if (auth.uid != targetUid) return false;
    if (newData['uid'] != targetUid) return false;
    final role = newData['role'];
    return role == 'Student' ||
        (auth.hasInstructorClaim && role == 'Instructor');
  }

  static bool canUpdateUser({
    required FirestoreAuthContext? auth,
    required String targetUid,
    required Map<String, dynamic> existingData,
    required Map<String, dynamic> newData,
  }) {
    if (auth == null) return false;
    if (auth.uid != targetUid) return false;
    if (newData['role'] != existingData['role']) return false;
    if (existingData.containsKey('uid') && newData['uid'] != existingData['uid']) {
      return false;
    }
    final affected = diffKeys(existingData, newData);
    return affected.every(allowedUserUpdateKeys.contains);
  }

  static bool canDeleteUser() => false;

  // ── /sessions/{sessionId} ─────────────────────────────────────────────────

  static bool _isSessionOwner(
    FirestoreAuthContext auth,
    Map<String, dynamic> sessionData,
  ) {
    final userId = sessionData['userId'];
    return userId == auth.uid || (auth.email != null && userId == auth.email);
  }

  static bool canCreateSession({
    required FirestoreAuthContext? auth,
    required Map<String, dynamic> newData,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    if (auth == null) return false;
    if (!hasNoPublicInstructorNote(newData)) return false;
    if (isInstructor(auth: auth, usersCollection: usersCollection)) {
      return true;
    }
    return _isSessionOwner(auth, newData) &&
        newData['feedbackStatus'] == 'Released' &&
        newData['isPractice'] == true;
  }

  static bool canReadSession({
    required FirestoreAuthContext? auth,
    required Map<String, dynamic> sessionData,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    if (auth == null) return false;
    if (isInstructor(auth: auth, usersCollection: usersCollection)) {
      return true;
    }
    return _isSessionOwner(auth, sessionData) &&
        sessionData['feedbackStatus'] == 'Released' &&
        hasNoPublicInstructorNote(sessionData);
  }

  static bool canUpdateSession({
    required FirestoreAuthContext? auth,
    required Map<String, dynamic> existingData,
    required Map<String, dynamic> newData,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    if (!hasNoPublicInstructorNote(newData)) return false;
    if (isInstructor(auth: auth, usersCollection: usersCollection)) {
      return true;
    }
    if (auth == null) return false;
    if (!_isSessionOwner(auth, existingData)) return false;
    if (existingData['isPractice'] != true) return false;
    if (existingData['feedbackStatus'] != 'Released') return false;
    final affected = diffKeys(existingData, newData);
    return affected.isNotEmpty &&
        affected.every(allowedStudentPracticeUpdateKeys.contains);
  }

  static bool canDeleteSession({
    required FirestoreAuthContext? auth,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    return isInstructor(auth: auth, usersCollection: usersCollection);
  }

  // ── /sessions/{sessionId}/private/{docId} ─────────────────────────────────

  static bool canReadPrivateInstructorNote({
    required FirestoreAuthContext? auth,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    return isInstructor(auth: auth, usersCollection: usersCollection);
  }

  static bool canWritePrivateInstructorNote({
    required FirestoreAuthContext? auth,
    required Map<String, Map<String, dynamic>> usersCollection,
  }) {
    return isInstructor(auth: auth, usersCollection: usersCollection);
  }
}

