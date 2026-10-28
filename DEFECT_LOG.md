# PRISM Defect Log (v3.0.0-midterm candidate)

Found during the bulk test (`BULK_TEST_CHECKLIST.md`). Update Status and Retest as each fix is verified on the phones.

| ID | Found in | Problem | Root cause | Fix (branch) | Status | Retest result |
|---|---|---|---|---|---|---|
| DEF-1 | A (My Sessions) | Student My Sessions failed with `PERMISSION_DENIED` | Student queries had no `feedbackStatus == 'Released'` filter, which the release-quarantine rule requires | `fix/sessions/student_query_release_filter` | Fixed, retest pending | |
| DEF-2 | B4 (Aspiration) | Remote Control screen flickered when aspiration started; the mirrored camera view kept resetting | The aspiration timer called `setState` ten times a second, which recreated the Firestore stream and showed a loading spinner in place of the camera view | `fix/remote/aspiration_flicker` | Fixed, retest pending | |
| DEF-3 | B10 (AI draft) | AI feedback fell back to the template draft (`aiValidationStatus = "Template Fallback"`, note `unsupported_number`) | The validator rejected valid derived numbers (angle deviation, rounded angles, rubric step numbers) | `fix/core/bulk_test_defects` | Fixed; partly verified | 2 of 4 retest sessions Passed. 1 fallback with `unsupported_number:14` (likely "14" for a 14.6 s duration). 1 fallback with `ai_unavailable` on a practice session with blood (see DEF-5). Template text no longer claims proper placement. |
| DEF-4 | B8 (Review screen) | Layout overflow in Detection Results (66 px) and the private note header (83 px); the template badge looked inconsistent with the rest of the UI | Long labels without flexible layout; badge style not matching the design system | `fix/feedback/validator_derived_numbers` | Fixed, retest pending | |
| DEF-5 | C / E (blood present) | After blood is observed the session should stop, but practice mode kept the withdrawal phase and scored it (withdrawal angle, score and "Matches"), and its AI text described the withdrawal. The instructor Stop path stored placeholder withdrawal values (score 1, "Deviates") that the review screen treats as real results | Bleeding stop was not applied consistently: no shared rule that withdrawal is not performed or scored when blood is observed | `fix/sessions/bleeding_stops_session` (or the open defects branch) | Open | |

Not defects: A3 "model cannot detect" was caused by running the app without `--dart-define-from-file=.env.json`; run with `.\run`.
