# GIT_WORKFLOW.md — PRISM Git Collaboration Guide
# All team members must follow this workflow for every change.

---

## Branch Naming Convention

```
main_task/module/short_description
```

| Main Task | Prefix |
|---|---|
| New feature | `feature` |
| Technical change (refactor, library swap) | `tech` |
| Bug fix | `fix` |
| Setup / configuration | `setup` |
| Official Release (Special Case) | `v` (e.g., `v1`) |

**Examples:**
```bash
feature/login/create_login_ui
feature/detection/insertion_angle_overlay
tech/login/change_auth_library
fix/login/color_of_button
fix/detection/camera_permission_crash
setup/firebase/firestore_rules
setup/openrouter/api_key_config
```

> Use **underscores** for spaces within the description.

---

## Commit Message Format

```
main_task(module): short description
```

**Examples:**
```bash
git commit -m "feature(login): create login ui"
git commit -m "feature(detection): add insertion angle overlay"
git commit -m "tech(login): change auth library to firebase"
git commit -m "fix(login): fix button color"
git commit -m "fix(detection): fix camera permission crash on android 12"
git commit -m "setup(firebase): configure firestore security rules"
git commit -m "setup(openrouter): add api key dart define config"
```

> Keep the description short and lowercase. No period at the end.

---

## Full Workflow (Every Time)

### Step 1 — Always pull latest main first
```bash
git checkout main
git pull origin main
```

### Step 2 — Create your feature branch
```bash
git checkout -b feature/your_module/your_description
```

### Step 3 — Do your work
Edit files, run the app, test on device.

### Step 4 — Stage and commit
```bash
git add .
git commit -m "feature(module): short description"
```

You can make multiple commits on your branch — commit often.

### Step 5 — Push to GitHub
```bash
git push origin feature/your_module/your_description
```

### Step 6 — Open a Pull Request (PR)
1. Go to the GitHub repo
2. Click **Compare & pull request**
3. Set base branch → `main`
4. Write a short description of what changed
5. Request review from Emmanuel (backend lead) or team lead
6. Merge only after approval

---

## Branch → Screen Assignment (UI team)

| Branch name | Screen file |
|---|---|
| `feature/login/create_login_ui` | `screens/auth/login_screen.dart` |
| `feature/register/create_register_ui` | `screens/auth/register_screen.dart` |
| `feature/injection_type/create_type_select_ui` | `screens/student/injection_type_screen.dart` |
| `feature/detection/create_camera_ui` | `screens/student/detection_screen.dart` |
| `feature/session_complete/create_results_ui` | `screens/student/session_complete_screen.dart` |
| `feature/my_sessions/create_session_list_ui` | `screens/student/my_sessions_screen.dart` |
| `feature/session_detail/create_detail_ui` | `screens/student/session_detail_screen.dart` |
| `feature/instructor_dashboard/create_dashboard_ui` | `screens/instructor/instructor_dashboard_screen.dart` |
| `feature/feedback_review/create_review_ui` | `screens/instructor/feedback_review_screen.dart` |

---

## Rules

- **Never push directly to `main`** — always use a PR
- **One screen per branch** — keeps PRs small and reviewable
- **Pull from main before starting a new branch** — avoids merge conflicts
- **Use underscores** in branch names and descriptions, not spaces or camelCase
- **Don't commit `.env.json`** — it's in `.gitignore` for a reason (API key)
- **Don't commit `build/`** — it's auto-generated
- **Agent Workflow:** When concluding work on a feature branch, ask the agent to generate a brief, bullet-style summary of the changes. You can copy this summary for your Pull Request description or final commit message.

---

## Quick Reference

```bash
# Start new work:
git checkout main && git pull origin main
git checkout -b feature/module/description

# Save work in progress:
git add . && git commit -m "feature(module): wip description"

# Push and open PR:
git push origin feature/module/description
# → go to GitHub → Compare & pull request
```

---

*GIT_WORKFLOW.md v1.0 — PRISM IT332-30, CIT-U, May 2026*
