import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/aspiration_outcome.dart';
import 'package:prism_app/core/firestore_security_policy.dart';
import 'package:prism_app/models/session_model.dart';
import 'package:prism_app/services/instructor_session_repository.dart';

SessionModel _sampleSession({
  String sessionId = 'session_101',
  String userId = 'student@cit.edu',
  String feedbackStatus = 'Pending',
  String aiFeedbackText = 'Initial AI feedback draft.',
  String aiFeedbackOriginal = 'Initial AI feedback draft.',
  String instructorNote = 'Private clinical observation: landmark slightly low.',
  bool isPractice = false,
}) {
  return SessionModel(
    sessionId: sessionId,
    userId: userId,
    studentName: 'Juan Dela Cruz',
    timestamp: Timestamp.now(),
    injectionType: 'IM',
    sectionName: isPractice ? 'Practice' : 'BSN-3A',
    partnerName: isPractice ? 'Self-Practice' : 'Maria Santos',
    insertionAngle: 89.2,
    insertionScore: 5,
    aspirationResult: 'No Bleeding',
    aspirationScore: 5,
    bleedingObserved: false,
    aspirationAngleDrift: 1.1,
    aspirationDuration: 5.0,
    motionSmoothness: 'Good',
    withdrawalAngle: 88.8,
    withdrawalScore: 5,
    correspondenceResult: 'Matches',
    angularDelta: 0.4,
    overallScore: 5,
    aiFeedbackText: aiFeedbackText,
    aiFeedbackOriginal: aiFeedbackOriginal,
    feedbackStatus: feedbackStatus,
    instructorNote: instructorNote,
    flagged: false,
    isPractice: isPractice,
  );
}

void main() {
  const studentAuth = FirestoreAuthContext(
    uid: 'student_uid_1',
    email: 'student@cit.edu',
  );
  const otherStudentAuth = FirestoreAuthContext(
    uid: 'student_uid_2',
    email: 'other@cit.edu',
  );
  const instructorAuth = FirestoreAuthContext(
    uid: 'instructor_uid_1',
    email: 'instructor@cit.edu',
  );
  const claimInstructorAuth = FirestoreAuthContext(
    uid: 'instructor_claim_uid',
    email: 'claim_instructor@cit.edu',
    tokenClaims: {'role': 'Instructor'},
  );

  final Map<String, Map<String, dynamic>> usersDb = {
    'student_uid_1': {
      'uid': 'student_uid_1',
      'fullName': 'Juan Dela Cruz',
      'email': 'student@cit.edu',
      'role': 'Student',
      'emailVerified': true,
      'authProvider': 'password',
      'hasPassword': true,
    },
    'student_uid_2': {
      'uid': 'student_uid_2',
      'fullName': 'Maria Santos',
      'email': 'other@cit.edu',
      'role': 'Student',
      'emailVerified': true,
      'authProvider': 'password',
      'hasPassword': true,
    },
    'instructor_uid_1': {
      'uid': 'instructor_uid_1',
      'fullName': 'Prof. Clinical Evaluator',
      'email': 'instructor@cit.edu',
      'role': 'Instructor',
      'emailVerified': true,
      'authProvider': 'password',
      'hasPassword': true,
    },
  };

  group('1. Unauthorized Role Changes (Task 2)', () {
    test('student self-registration with Student role is allowed', () {
      const newStudentAuth = FirestoreAuthContext(
        uid: 'new_student_uid',
        email: 'newstudent@cit.edu',
      );
      final allowed = FirestoreSecurityPolicy.canCreateUser(
        auth: newStudentAuth,
        targetUid: 'new_student_uid',
        newData: {
          'uid': 'new_student_uid',
          'fullName': 'New Student',
          'email': 'newstudent@cit.edu',
          'role': 'Student',
        },
      );
      expect(allowed, isTrue);
    });

    test('student cannot self-register with Instructor role', () {
      const attackerAuth = FirestoreAuthContext(
        uid: 'attacker_uid',
        email: 'attacker@cit.edu',
      );
      final allowed = FirestoreSecurityPolicy.canCreateUser(
        auth: attackerAuth,
        targetUid: 'attacker_uid',
        newData: {
          'uid': 'attacker_uid',
          'fullName': 'Attacker',
          'email': 'attacker@cit.edu',
          'role': 'Instructor',
        },
      );
      expect(allowed, isFalse);
    });

    test('student cannot promote themselves to Instructor via profile update', () {
      final existing = usersDb['student_uid_1']!;
      final escalated = {
        ...existing,
        'role': 'Instructor',
      };
      final allowed = FirestoreSecurityPolicy.canUpdateUser(
        auth: studentAuth,
        targetUid: 'student_uid_1',
        existingData: existing,
        newData: escalated,
      );
      expect(allowed, isFalse);
    });

    test('student can update normal profile fields (fullName, hasPassword) without changing role', () {
      final existing = usersDb['student_uid_1']!;
      final updatedProfile = {
        ...existing,
        'fullName': 'Juan M. Dela Cruz',
        'hasPassword': true,
      };
      final allowed = FirestoreSecurityPolicy.canUpdateUser(
        auth: studentAuth,
        targetUid: 'student_uid_1',
        existingData: existing,
        newData: updatedProfile,
      );
      expect(allowed, isTrue);
    });

    test('student cannot delete their user profile document to recreate with higher role', () {
      expect(FirestoreSecurityPolicy.canDeleteUser(), isFalse);
    });
  });

  group('2. Legitimate Instructor Access (Task 2)', () {
    test('existing provisioned instructor retains Instructor access and can update fullName', () {
      expect(
        FirestoreSecurityPolicy.isInstructor(
          auth: instructorAuth,
          usersCollection: usersDb,
        ),
        isTrue,
      );

      final existingInstructor = usersDb['instructor_uid_1']!;
      final updatedInstructor = {
        ...existingInstructor,
        'fullName': 'Prof. Clinical Evaluator, RN, MAN',
      };

      expect(
        FirestoreSecurityPolicy.canUpdateUser(
          auth: instructorAuth,
          targetUid: 'instructor_uid_1',
          existingData: existingInstructor,
          newData: updatedInstructor,
        ),
        isTrue,
      );
    });

    test('instructor provisioned via custom token claim is authorized and can create profile', () {
      expect(
        FirestoreSecurityPolicy.isInstructor(
          auth: claimInstructorAuth,
          usersCollection: usersDb,
        ),
        isTrue,
      );

      expect(
        FirestoreSecurityPolicy.canCreateUser(
          auth: claimInstructorAuth,
          targetUid: 'instructor_claim_uid',
          newData: {
            'uid': 'instructor_claim_uid',
            'fullName': 'Claim Instructor',
            'email': 'claim_instructor@cit.edu',
            'role': 'Instructor',
          },
        ),
        isTrue,
      );
    });

    test('instructor can read student profiles and pending/released sessions', () {
      expect(
        FirestoreSecurityPolicy.canReadUser(
          auth: instructorAuth,
          targetUid: 'student_uid_1',
          usersCollection: usersDb,
        ),
        isTrue,
      );

      final pendingSession = _sampleSession(feedbackStatus: 'Pending').toFirestore();
      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: instructorAuth,
          sessionData: pendingSession,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });
  });

  group('3. Student Access to Released Sessions (Task 3 & Task 4)', () {
    test('student can read their own Released session when public instructorNote is empty', () {
      final releasedSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Released',
      ).toFirestore();

      expect(releasedSession['instructorNote'], isEmpty);
      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: studentAuth,
          sessionData: releasedSession,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });

    test('student cannot read their own Pending or Failed session before instructor release', () {
      final pendingSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Pending',
      ).toFirestore();
      final failedSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Feedback Generation Failed',
      ).toFirestore();

      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: studentAuth,
          sessionData: pendingSession,
          usersCollection: usersDb,
        ),
        isFalse,
      );
      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: studentAuth,
          sessionData: failedSession,
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });

    test('student cannot read another student\'s Released session', () {
      final releasedSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Released',
      ).toFirestore();

      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: otherStudentAuth,
          sessionData: releasedSession,
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });
  });

  group('4. Denial of Student Access to Private Notes (Task 3)', () {
    test('student is denied direct read and write access to sessions/{sessionId}/private/instructor_note', () {
      expect(
        FirestoreSecurityPolicy.canReadPrivateInstructorNote(
          auth: studentAuth,
          usersCollection: usersDb,
        ),
        isFalse,
      );
      expect(
        FirestoreSecurityPolicy.canWritePrivateInstructorNote(
          auth: studentAuth,
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });

    test('SessionModel.toFirestore() scrubs instructorNote from public session document while preserving it in toPrivateNoteFirestore()', () {
      final session = _sampleSession(
        instructorNote: 'Confidential instructor note: student was nervous during landmarking.',
      );

      final publicMap = session.toFirestore();
      final privateMap = session.toPrivateNoteFirestore();

      expect(publicMap['instructorNote'], equals(''));
      expect(
        privateMap['instructorNote'],
        equals('Confidential instructor note: student was nervous during landmarking.'),
      );
    });

    test('createBleedingStoppedSession does not leak private instructor note into public toFirestore() payload', () {
      final stoppedSession = createBleedingStoppedSession(
        userId: 'student@cit.edu',
        studentName: 'Juan Dela Cruz',
        injectionType: 'IM',
        insertionAngle: 88.0,
        insertionScore: 5,
        aspirationAngleDrift: 1.0,
        aspirationDuration: 4.0,
        isPractice: false,
      );

      expect(stoppedSession.instructorNote, isNotEmpty);
      expect(stoppedSession.toFirestore()['instructorNote'], equals(''));
      expect(
        stoppedSession.toPrivateNoteFirestore()['instructorNote'],
        equals('Instructor cancelled session: Patient bleeding detected during aspiration.'),
      );
    });

    test('unmigrated historical session with non-empty public instructorNote is quarantined from student reads but accessible to instructors', () {
      final legacyUnmigratedData = <String, dynamic>{
        ..._sampleSession(
          userId: 'student@cit.edu',
          feedbackStatus: 'Released',
        ).toFirestore(),
        'instructorNote': 'Legacy unmigrated private note on parent doc',
      };

      // Student cannot read unmigrated session while private note is still on public document
      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: studentAuth,
          sessionData: legacyUnmigratedData,
          usersCollection: usersDb,
        ),
        isFalse,
      );

      // Instructor can read and migrate it
      expect(
        FirestoreSecurityPolicy.canReadSession(
          auth: instructorAuth,
          sessionData: legacyUnmigratedData,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });
  });

  group('5. Instructor Feedback Editing & Note Isolation (Task 3 & Task 4)', () {
    test('instructor can read and write private instructor notes subcollection', () {
      expect(
        FirestoreSecurityPolicy.canReadPrivateInstructorNote(
          auth: instructorAuth,
          usersCollection: usersDb,
        ),
        isTrue,
      );
      expect(
        FirestoreSecurityPolicy.canWritePrivateInstructorNote(
          auth: instructorAuth,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });

    test('instructor can edit aiFeedbackText and release session while preserving aiFeedbackOriginal and keeping public instructorNote empty', () {
      final session = _sampleSession(
        feedbackStatus: 'Pending',
        aiFeedbackText: 'Original AI draft text.',
        aiFeedbackOriginal: 'Original AI draft text.',
      );
      final before = session.toFirestore();
      final after = session
          .copyWith(
            aiFeedbackText: 'Instructor-edited clinical feedback for student.',
            feedbackStatus: 'Released',
          )
          .toFirestore();

      expect(after['aiFeedbackOriginal'], equals('Original AI draft text.'));
      expect(after['aiFeedbackText'], equals('Instructor-edited clinical feedback for student.'));
      expect(after['instructorNote'], equals(''));
      expect(
        FirestoreSecurityPolicy.canUpdateSession(
          auth: instructorAuth,
          existingData: before,
          newData: after,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });

    test('writing a non-empty instructorNote directly to public sessions/{sessionId} document is rejected even for instructors', () {
      final session = _sampleSession(feedbackStatus: 'Pending');
      final before = session.toFirestore();
      final invalidPublicWrite = <String, dynamic>{
        ...before,
        'instructorNote': 'Should not be stored on public session doc',
      };

      expect(
        FirestoreSecurityPolicy.canUpdateSession(
          auth: instructorAuth,
          existingData: before,
          newData: invalidPublicWrite,
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });
  });

  group('6. Practice Mode Permissions (Task 4)', () {
    test('student can create their own Practice session with Released status and empty instructorNote', () {
      final practiceSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Released',
        isPractice: true,
        instructorNote: '',
      );

      expect(
        FirestoreSecurityPolicy.canCreateSession(
          auth: studentAuth,
          newData: practiceSession.toFirestore(),
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });

    test('student cannot create an Official (non-practice) session', () {
      final officialSession = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Pending',
        isPractice: false,
      );

      expect(
        FirestoreSecurityPolicy.canCreateSession(
          auth: studentAuth,
          newData: officialSession.toFirestore(),
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });

    test('student can update AI feedback fields on their own Practice session', () {
      final initialPractice = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Released',
        aiFeedbackText: '',
        aiFeedbackOriginal: '',
        isPractice: true,
      ).toFirestore();

      final populatedPractice = <String, dynamic>{
        ...initialPractice,
        'aiFeedbackText': 'Generated practice AI guide.',
        'aiFeedbackOriginal': 'Generated practice AI guide.',
        'aiValidationStatus': 'Passed',
        'aiValidationNotes': <String>[],
      };

      expect(
        FirestoreSecurityPolicy.canUpdateSession(
          auth: studentAuth,
          existingData: initialPractice,
          newData: populatedPractice,
          usersCollection: usersDb,
        ),
        isTrue,
      );
    });

    test('student cannot tamper with scores, angles, or isPractice on Practice session', () {
      final initialPractice = _sampleSession(
        userId: 'student@cit.edu',
        feedbackStatus: 'Released',
        isPractice: true,
      ).toFirestore();

      final tamperedScore = <String, dynamic>{
        ...initialPractice,
        'overallScore': 5,
        'insertionScore': 5,
        'insertionAngle': 90.0,
      };
      // Ensure at least one score/angle differs from initial
      tamperedScore['insertionAngle'] = 90.0;

      expect(
        FirestoreSecurityPolicy.canUpdateSession(
          auth: studentAuth,
          existingData: initialPractice,
          newData: tamperedScore,
          usersCollection: usersDb,
        ),
        isFalse,
      );
    });
  });

  group('7. Firestore Rules File Verification (firestore.rules)', () {
    test('firestore.rules enforces role immutability, Student-only self-registration, and private note subcollection isolation', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue);
      final content = rulesFile.readAsStringSync();

      // Task 2: Prevent Instructor Role Escalation
      expect(content, contains("request.resource.data.get('role', '') == 'Student'"));
      expect(
        content,
        contains("request.resource.data.get('role', '') == resource.data.get('role', '')"),
      );
      expect(content, contains('allow delete: if false;'));

      // Task 3: Protect Private Instructor Notes
      expect(content, contains('function hasNoPublicInstructorNote(data)'));
      expect(
        content,
        contains("match /${InstructorSessionRepository.privateCollectionName}/{docId}"),
      );
      expect(content, contains('hasNoPublicInstructorNote(resource.data)'));
      expect(content, contains('hasNoPublicInstructorNote(request.resource.data)'));
    });
  });
}

