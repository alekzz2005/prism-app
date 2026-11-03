import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  writeBatch,
   setLogLevel,
} from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_PATH = resolve(__dirname, '../../firestore.rules');
const PROJECT_ID = 'prism-app-ae2d6';

// Silence expected Firestore SDK permission-denied console noise during negative assertions
setLogLevel('error');

let testEnv;

const STUDENT_UID = 'student_uid_1';
const STUDENT_EMAIL = 'student1@cit.edu';
const OTHER_STUDENT_UID = 'student_uid_2';
const OTHER_STUDENT_EMAIL = 'student2@cit.edu';
const INSTRUCTOR_UID = 'instructor_uid_1';
const INSTRUCTOR_EMAIL = 'instructor@cit.edu';

function studentContext() {
  return testEnv.authenticatedContext(STUDENT_UID, {
    email: STUDENT_EMAIL,
  });
}

function otherStudentContext() {
  return testEnv.authenticatedContext(OTHER_STUDENT_UID, {
    email: OTHER_STUDENT_EMAIL,
  });
}

function instructorContext() {
  return testEnv.authenticatedContext(INSTRUCTOR_UID, {
    email: INSTRUCTOR_EMAIL,
  });
}

function claimInstructorContext(uid = 'claim_instructor_uid') {
  return testEnv.authenticatedContext(uid, {
    email: 'claim_instructor@cit.edu',
    role: 'Instructor',
  });
}

function unauthenticatedContext() {
  return testEnv.unauthenticatedContext();
}

async function seedBaseUsers() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    await setDoc(doc(adminDb, 'users', STUDENT_UID), {
      uid: STUDENT_UID,
      fullName: 'Juan Dela Cruz',
      email: STUDENT_EMAIL,
      role: 'Student',
      createdAt: new Date().toISOString(),
      emailVerified: true,
      authProvider: 'password',
      hasPassword: true,
    });
    await setDoc(doc(adminDb, 'users', OTHER_STUDENT_UID), {
      uid: OTHER_STUDENT_UID,
      fullName: 'Maria Santos',
      email: OTHER_STUDENT_EMAIL,
      role: 'Student',
      createdAt: new Date().toISOString(),
      emailVerified: true,
      authProvider: 'password',
      hasPassword: true,
    });
    await setDoc(doc(adminDb, 'users', INSTRUCTOR_UID), {
      uid: INSTRUCTOR_UID,
      fullName: 'Clinical Instructor',
      email: INSTRUCTOR_EMAIL,
      role: 'Instructor',
      createdAt: new Date().toISOString(),
      emailVerified: true,
      authProvider: 'password',
      hasPassword: true,
    });
  });
}

function buildSessionPayload({
  userId = STUDENT_EMAIL,
  studentName = 'Juan Dela Cruz',
  feedbackStatus = 'Released',
  isPractice = false,
  instructorNote = '',
  aiFeedbackText = 'Validated clinical AI feedback.',
  aiFeedbackOriginal = 'Validated clinical AI feedback.',
  overallScore = 5,
} = {}) {
  return {
    userId,
    studentName,
    timestamp: new Date().toISOString(),
    injectionType: 'IM',
    sectionName: isPractice ? 'Practice' : 'BSN-3A',
    partnerName: isPractice ? 'Self-Practice' : 'Maria Santos',
    insertionAngle: 89.4,
    insertionScore: 5,
    aspirationResult: 'No Bleeding',
    aspirationScore: 5,
    bleedingObserved: false,
    aspirationAngleDrift: 1.1,
    aspirationDuration: 5.0,
    motionSmoothness: 'Good',
    withdrawalAngle: 89.0,
    withdrawalScore: 5,
    correspondenceResult: 'Matches',
    angularDelta: 0.4,
    overallScore,
    aiFeedbackText,
    aiFeedbackOriginal,
    feedbackStatus,
    instructorNote,
    flagged: false,
    aiValidationStatus: 'Passed',
    aiValidationNotes: [],
    isPractice,
  };
}

describe('PRISM v3.0.0 Firestore Emulator Security Rules Suite', () => {
  before(async () => {
    const rules = readFileSync(RULES_PATH, 'utf8');
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules,
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedBaseUsers();
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  // ── A. Instructor Role Escalation ──────────────────────────────────────────
  describe('A. Instructor Role Escalation Prevention', () => {
    it('1. Student cannot self-register as Instructor', async () => {
      const newUid = 'new_signup_student';
      const db = testEnv
        .authenticatedContext(newUid, { email: 'new@cit.edu' })
        .firestore();

      await assertFails(
        setDoc(doc(db, 'users', newUid), {
          uid: newUid,
          fullName: 'Escalation Attacker',
          email: 'new@cit.edu',
          role: 'Instructor',
          emailVerified: false,
          authProvider: 'password',
          hasPassword: true,
        }),
      );

      // Legitimate Student self-registration succeeds
      await assertSucceeds(
        setDoc(doc(db, 'users', newUid), {
          uid: newUid,
          fullName: 'Legitimate Student',
          email: 'new@cit.edu',
          role: 'Student',
          emailVerified: false,
          authProvider: 'password',
          hasPassword: true,
        }),
      );
    });

    it('2. Student cannot change their role to Instructor via update', async () => {
      const db = studentContext().firestore();

      await assertFails(
        updateDoc(doc(db, 'users', STUDENT_UID), {
          role: 'Instructor',
        }),
      );

      await assertFails(
        setDoc(
          doc(db, 'users', STUDENT_UID),
          { role: 'Instructor', fullName: 'Juan Dela Cruz' },
          { merge: true },
        ),
      );
    });

    it('3. Student can update permitted profile fields (fullName, hasPassword, emailVerified)', async () => {
      const db = studentContext().firestore();

      await assertSucceeds(
        updateDoc(doc(db, 'users', STUDENT_UID), {
          fullName: 'Juan M. Dela Cruz',
          hasPassword: true,
          emailVerified: true,
        }),
      );

      const snap = await getDoc(doc(db, 'users', STUDENT_UID));
      assert.equal(snap.data().fullName, 'Juan M. Dela Cruz');
      assert.equal(snap.data().role, 'Student');
    });

    it('4. Student cannot delete and recreate their profile to bypass role restrictions', async () => {
      const db = studentContext().firestore();

      await assertFails(deleteDoc(doc(db, 'users', STUDENT_UID)));
    });

    it('5. Existing legitimate Instructor accounts retain authorized access and profile update rights', async () => {
      const instDb = instructorContext().firestore();

      // Can update own fullName while retaining role == 'Instructor'
      await assertSucceeds(
        updateDoc(doc(instDb, 'users', INSTRUCTOR_UID), {
          fullName: 'Prof. Clinical Evaluator, RN, MAN',
        }),
      );

      // Can read student user profiles (e.g. resolving email to UID)
      await assertSucceeds(getDoc(doc(instDb, 'users', STUDENT_UID)));

      // Custom-claim provisioned instructor can also create their Instructor profile
      const claimDb = claimInstructorContext('claim_inst_1').firestore();
      await assertSucceeds(
        setDoc(doc(claimDb, 'users', 'claim_inst_1'), {
          uid: 'claim_inst_1',
          fullName: 'Claim Provisioned Instructor',
          email: 'claim_instructor@cit.edu',
          role: 'Instructor',
          emailVerified: true,
          authProvider: 'password',
          hasPassword: true,
        }),
      );
    });

    it('6. Student cannot modify immutable uid or createdAt fields on their user profile', async () => {
      const db = studentContext().firestore();

      await assertFails(
        updateDoc(doc(db, 'users', STUDENT_UID), {
          uid: 'spoofed_uid',
        }),
      );

      await assertFails(
        updateDoc(doc(db, 'users', STUDENT_UID), {
          createdAt: new Date().toISOString(),
        }),
      );
    });
  });

  // ── B. Session Access ──────────────────────────────────────────────────────
  describe('B. Session Access Control', () => {
    it('7. Student can read their own Released session', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'session_released_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: '',
          }),
        );
      });

      const db = studentContext().firestore();
      const snap = await assertSucceeds(
        getDoc(doc(db, 'sessions', 'session_released_1')),
      );
      assert.equal(snap.exists(), true);
      assert.equal(snap.data().feedbackStatus, 'Released');
    });

    it('8. Student cannot read their own Pending or Failed session', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'session_pending_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Pending',
          }),
        );
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'session_failed_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Feedback Generation Failed',
          }),
        );
      });

      const db = studentContext().firestore();
      await assertFails(getDoc(doc(db, 'sessions', 'session_pending_1')));
      await assertFails(getDoc(doc(db, 'sessions', 'session_failed_1')));
    });

    it('9. Student cannot read another student\'s Released session', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'session_student_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
          }),
        );
      });

      const otherDb = otherStudentContext().firestore();
      await assertFails(getDoc(doc(otherDb, 'sessions', 'session_student_1')));
    });

    it('10. Instructor can create, read, update, and delete official assessment records', async () => {
      const instDb = instructorContext().firestore();
      const sessionRef = doc(instDb, 'sessions', 'official_session_1');

      await assertSucceeds(
        setDoc(
          sessionRef,
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Pending',
            isPractice: false,
            instructorNote: '',
          }),
        ),
      );

      await assertSucceeds(getDoc(sessionRef));

      await assertSucceeds(
        updateDoc(sessionRef, {
          aiFeedbackText: 'Instructor-reviewed clinical feedback.',
          feedbackStatus: 'Released',
          instructorNote: '',
        }),
      );

      await assertSucceeds(deleteDoc(sessionRef));
    });
  });

  // ── C. Private Instructor Notes ────────────────────────────────────────────
  describe('C. Private Instructor Notes Isolation & Migration', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const adminDb = ctx.firestore();
        await setDoc(
          doc(adminDb, 'sessions', 'session_with_priv_note'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: '',
          }),
        );
        await setDoc(
          doc(
            adminDb,
            'sessions',
            'session_with_priv_note',
            'private',
            'instructor_note',
          ),
          {
            instructorNote:
              'Confidential faculty note: student hesitated before aspiration.',
            updatedAt: new Date().toISOString(),
          },
        );
      });
    });

    it('11. Student cannot read sessions/{sessionId}/private/instructor_note', async () => {
      const db = studentContext().firestore();
      await assertFails(
        getDoc(
          doc(
            db,
            'sessions',
            'session_with_priv_note',
            'private',
            'instructor_note',
          ),
        ),
      );
    });

    it('12. Student cannot write to the private note document', async () => {
      const db = studentContext().firestore();
      await assertFails(
        setDoc(
          doc(
            db,
            'sessions',
            'session_with_priv_note',
            'private',
            'instructor_note',
          ),
          { instructorNote: 'Tampered by student' },
        ),
      );
      await assertFails(
        updateDoc(
          doc(
            db,
            'sessions',
            'session_with_priv_note',
            'private',
            'instructor_note',
          ),
          { instructorNote: 'Tampered by student' },
        ),
      );
    });

    it('13. Instructor can read and update private notes', async () => {
      const instDb = instructorContext().firestore();
      const noteRef = doc(
        instDb,
        'sessions',
        'session_with_priv_note',
        'private',
        'instructor_note',
      );

      const snap = await assertSucceeds(getDoc(noteRef));
      assert.equal(
        snap.data().instructorNote,
        'Confidential faculty note: student hesitated before aspiration.',
      );

      await assertSucceeds(
        setDoc(
          noteRef,
          {
            instructorNote: 'Updated confidential note after post-conference.',
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        ),
      );
    });

    it('14. Student cannot read a legacy Released session containing a non-empty public instructorNote', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'legacy_unmigrated_session'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: 'Legacy private note still on parent doc',
          }),
        );
      });

      const stuDb = studentContext().firestore();
      await assertFails(
        getDoc(doc(stuDb, 'sessions', 'legacy_unmigrated_session')),
      );
    });

    it('15. Student can read that session after the note has been migrated and removed from the public document', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'legacy_migrated_session'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: 'Legacy private note to migrate',
          }),
        );
      });

      const stuDb = studentContext().firestore();
      const instDb = instructorContext().firestore();

      // Quarantined prior to migration
      await assertFails(
        getDoc(doc(stuDb, 'sessions', 'legacy_migrated_session')),
      );

      // Instructor executes atomic batch migration (matching migrateLegacyInstructorNotes)
      const legacySnap = await assertSucceeds(
        getDoc(doc(instDb, 'sessions', 'legacy_migrated_session')),
      );
      const legacyNote = legacySnap.data().instructorNote;

      const batch = writeBatch(instDb);
      batch.set(
        doc(
          instDb,
          'sessions',
          'legacy_migrated_session',
          'private',
          'instructor_note',
        ),
        {
          instructorNote: legacyNote,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      batch.update(doc(instDb, 'sessions', 'legacy_migrated_session'), {
        instructorNote: '',
      });
      await assertSucceeds(batch.commit());

      // Now student can read the public session (with empty instructorNote)
      const releasedSnap = await assertSucceeds(
        getDoc(doc(stuDb, 'sessions', 'legacy_migrated_session')),
      );
      assert.equal(releasedSnap.data().instructorNote, '');

      // Student still cannot read the migrated private note subcollection doc
      await assertFails(
        getDoc(
          doc(
            stuDb,
            'sessions',
            'legacy_migrated_session',
            'private',
            'instructor_note',
          ),
        ),
      );

      // Instructor can read the migrated private note
      const privSnap = await assertSucceeds(
        getDoc(
          doc(
            instDb,
            'sessions',
            'legacy_migrated_session',
            'private',
            'instructor_note',
          ),
        ),
      );
      assert.equal(privSnap.data().instructorNote, 'Legacy private note to migrate');
    });

    it('16. Even Instructor cannot write a non-empty instructorNote onto the public sessions/{sessionId} document', async () => {
      const instDb = instructorContext().firestore();
      await assertFails(
        setDoc(
          doc(instDb, 'sessions', 'bad_public_note_session'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Pending',
            instructorNote: 'Should be rejected on public session document',
          }),
        ),
      );
    });
  });

  // ── D. Practice Mode ───────────────────────────────────────────────────────
  describe('D. Student Practice Mode Permissions', () => {
    it('17. Student can create their own valid Practice Mode session', async () => {
      const stuDb = studentContext().firestore();

      await assertSucceeds(
        setDoc(
          doc(stuDb, 'sessions', 'practice_session_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            isPractice: true,
            instructorNote: '',
            aiFeedbackText: '',
            aiFeedbackOriginal: '',
          }),
        ),
      );
    });

    it('18. Student cannot create an Official session (isPractice == false or Pending)', async () => {
      const stuDb = studentContext().firestore();

      await assertFails(
        setDoc(
          doc(stuDb, 'sessions', 'fake_official_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            isPractice: false,
            instructorNote: '',
          }),
        ),
      );

      await assertFails(
        setDoc(
          doc(stuDb, 'sessions', 'fake_official_2'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Pending',
            isPractice: true,
            instructorNote: '',
          }),
        ),
      );
    });

    it('19. Student can update permitted AI feedback fields on their own Practice Mode session', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'practice_session_ai'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            isPractice: true,
            instructorNote: '',
            aiFeedbackText: '',
            aiFeedbackOriginal: '',
          }),
        );
      });

      const stuDb = studentContext().firestore();
      await assertSucceeds(
        updateDoc(doc(stuDb, 'sessions', 'practice_session_ai'), {
          aiFeedbackText: 'Practice AI guide generated.',
          aiFeedbackOriginal: 'Practice AI guide generated.',
          aiValidationStatus: 'Passed',
          aiValidationNotes: [],
        }),
      );
    });

    it('20. Student cannot modify protected assessment fields (scores, angles, isPractice, feedbackStatus) on Practice Mode session', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'practice_session_tamper'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            isPractice: true,
            instructorNote: '',
            overallScore: 2,
          }),
        );
      });

      const stuDb = studentContext().firestore();

      await assertFails(
        updateDoc(doc(stuDb, 'sessions', 'practice_session_tamper'), {
          overallScore: 5,
        }),
      );

      await assertFails(
        updateDoc(doc(stuDb, 'sessions', 'practice_session_tamper'), {
          insertionAngle: 90.0,
          insertionScore: 5,
        }),
      );

      await assertFails(
        updateDoc(doc(stuDb, 'sessions', 'practice_session_tamper'), {
          isPractice: false,
        }),
      );

      await assertFails(
        deleteDoc(doc(stuDb, 'sessions', 'practice_session_tamper')),
      );
    });
  });

  // ── E. Additional Security Checks & Multi-Session Migration ────────────────
  describe('E. Additional Security Checks & Multi-Session Migration Compatibility', () => {
    it('21. Unauthenticated users cannot access protected records', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), 'sessions', 'unauth_test_session'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
          }),
        );
      });

      const anonDb = unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(anonDb, 'users', STUDENT_UID)));
      await assertFails(getDoc(doc(anonDb, 'sessions', 'unauth_test_session')));
      await assertFails(
        getDoc(
          doc(
            anonDb,
            'sessions',
            'unauth_test_session',
            'private',
            'instructor_note',
          ),
        ),
      );
      await assertFails(getDoc(doc(anonDb, 'live_sessions', INSTRUCTOR_UID)));
      await assertFails(
        getDoc(
          doc(
            anonDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
          ),
        ),
      );
      await assertFails(
        getDoc(doc(anonDb, 'password_resets', STUDENT_EMAIL)),
      );
    });

    it('22. Student cannot access instructor rosters', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const adminDb = ctx.firestore();
        await setDoc(
          doc(
            adminDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
          ),
          { name: 'BSN-3A' },
        );
        await setDoc(
          doc(
            adminDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
            'students',
            'stu_1',
          ),
          {
            firstName: 'Juan',
            lastName: 'Dela Cruz',
            email: STUDENT_EMAIL,
          },
        );
      });

      const stuDb = studentContext().firestore();
      await assertFails(
        getDoc(
          doc(
            stuDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
          ),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            stuDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
            'students',
            'stu_1',
          ),
        ),
      );
      await assertFails(
        setDoc(
          doc(
            stuDb,
            'instructor_roster',
            INSTRUCTOR_UID,
            'sections',
            'BSN-3A',
            'students',
            'stu_2',
          ),
          { firstName: 'Fake', lastName: 'Student', email: 'fake@cit.edu' },
        ),
      );
    });

    it('23. Student cannot access instructor live sessions or WebRTC signaling subcollections', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const adminDb = ctx.firestore();
        await setDoc(doc(adminDb, 'live_sessions', INSTRUCTOR_UID), {
          studentName: 'Juan Dela Cruz',
          studentEmail: STUDENT_EMAIL,
          injectionType: 'IM',
          targetAngle: 90.0,
          phase: 'insertion',
          currentAngle: 88.5,
        });
        await setDoc(
          doc(
            adminDb,
            'live_sessions',
            INSTRUCTOR_UID,
            'ice_candidates',
            'cand_1',
          ),
          { candidate: 'candidate:1 1 UDP 2122252543 192.168.1.10 54321 typ host' },
        );
      });

      const stuDb = studentContext().firestore();
      await assertFails(getDoc(doc(stuDb, 'live_sessions', INSTRUCTOR_UID)));
      await assertFails(
        updateDoc(doc(stuDb, 'live_sessions', INSTRUCTOR_UID), {
          currentAngle: 90.0,
        }),
      );
      await assertFails(
        getDoc(
          doc(
            stuDb,
            'live_sessions',
            INSTRUCTOR_UID,
            'ice_candidates',
            'cand_1',
          ),
        ),
      );
    });

    it('24. Multi-session migration preserves existing private notes without overwriting and migrates unmigrated notes under active security rules', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const adminDb = ctx.firestore();
        // Session 1: Legacy note only on public doc
        await setDoc(
          doc(adminDb, 'sessions', 'mig_session_1'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: 'Legacy note 1 from parent doc',
          }),
        );
        // Session 2: Both legacy note on public doc AND newer note already in private/instructor_note
        await setDoc(
          doc(adminDb, 'sessions', 'mig_session_2'),
          buildSessionPayload({
            userId: STUDENT_EMAIL,
            feedbackStatus: 'Released',
            instructorNote: 'Stale legacy note 2 on parent doc',
          }),
        );
        await setDoc(
          doc(
            adminDb,
            'sessions',
            'mig_session_2',
            'private',
            'instructor_note',
          ),
          {
            instructorNote: 'Authoritative newer private note 2',
            updatedAt: new Date().toISOString(),
          },
        );
      });

      const instDb = instructorContext().firestore();
      const stuDb = studentContext().firestore();

      // Run exact logic of InstructorSessionRepository.migrateLegacyInstructorNotes()
      const sessionsSnap = await assertSucceeds(
        getDocs(collection(instDb, 'sessions')),
      );
      const batch = writeBatch(instDb);

      for (const sessionDoc of sessionsSnap.docs) {
        const data = sessionDoc.data();
        const legacyNote = data.instructorNote ?? '';
        if (!legacyNote) continue;

        const privRef = doc(
          instDb,
          'sessions',
          sessionDoc.id,
          'private',
          'instructor_note',
        );
        const existingPriv = await assertSucceeds(getDoc(privRef));
        const existingNote = existingPriv.exists()
          ? existingPriv.data().instructorNote
          : null;

        if ((!existingNote || existingNote.trim() === '') && legacyNote.trim() !== '') {
          batch.set(
            privRef,
            {
              instructorNote: legacyNote,
              updatedAt: new Date().toISOString(),
            },
            { merge: true },
          );
        }
        batch.update(sessionDoc.ref, { instructorNote: '' });
      }

      await assertSucceeds(batch.commit());

      // Verify Session 1 private note was migrated and parent scrubbed
      const priv1 = await assertSucceeds(
        getDoc(
          doc(instDb, 'sessions', 'mig_session_1', 'private', 'instructor_note'),
        ),
      );
      assert.equal(priv1.data().instructorNote, 'Legacy note 1 from parent doc');

      // Verify Session 2 existing private note was NOT overwritten
      const priv2 = await assertSucceeds(
        getDoc(
          doc(instDb, 'sessions', 'mig_session_2', 'private', 'instructor_note'),
        ),
      );
      assert.equal(
        priv2.data().instructorNote,
        'Authoritative newer private note 2',
      );

      // Verify student can now read both released sessions and sees empty instructorNote
      const stuSnap1 = await assertSucceeds(
        getDoc(doc(stuDb, 'sessions', 'mig_session_1')),
      );
      const stuSnap2 = await assertSucceeds(
        getDoc(doc(stuDb, 'sessions', 'mig_session_2')),
      );
      assert.equal(stuSnap1.data().instructorNote, '');
      assert.equal(stuSnap2.data().instructorNote, '');
    });
  });
});

