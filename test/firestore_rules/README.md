# PRISM Firestore Emulator Security Rules Test Suite

This directory contains the independent Firebase Firestore Emulator verification suite for PRISM (`v3.0.0-midterm`). It executes real read, write, update, delete, and batch-migration operations against the local Firestore Emulator using [`@firebase/rules-unit-testing`](https://www.npmjs.com/package/@firebase/rules-unit-testing) and Node.js's built-in test runner (`node:test`) to validate [`../../firestore.rules`](../../firestore.rules).

---

## 1. Prerequisites

Ensure the following tools are installed on your workstation:

| Tool | Minimum / Verified Version | Check Command |
|---|---|---|
| **Node.js** | v20+ (`v22.19.0` verified) | `node --version` |
| **npm** | v10+ (`10.9.3` verified) | `npm --version` |
| **Java (JDK/JRE)** | v17+ (`22.0.2` verified, required by Firestore Emulator JAR) | `java -version` |
| **Firebase CLI** | v13+ (`15.34.2` verified) | `firebase --version` |

---

## 2. Installation

From the repository root (`d:\GitHub Repositories\prism-app`), install the test dependencies inside `test/firestore_rules`:

```powershell
cd test/firestore_rules
npm install
cd ../..
```

---

## 3. Running the Firestore Emulator Security Tests

### Option A — Single-Command Automated Run (`emulators:exec`)

From the **repository root**, start the local Firestore Emulator (`127.0.0.1:8080`), execute all 24 security-rule tests, and automatically shut down the emulator when finished:

```powershell
firebase emulators:exec --only firestore --project prism-app-ae2d6 "node --test test/firestore_rules/firestore_rules.test.mjs"
```

Or from inside `test/firestore_rules`:

```powershell
npm test
```

### Option B — Manual Two-Terminal Run

1. **Terminal 1 (Start Firestore Emulator):**
   ```powershell
   firebase emulators:start --only firestore --project prism-app-ae2d6
   ```
2. **Terminal 2 (Execute Test Suite):**
   ```powershell
   node --test test/firestore_rules/firestore_rules.test.mjs
   ```

---

## 4. Expected Output

All 24 emulator-backed tests across 5 suites (`A` through `E`) should pass with zero failures and zero Firebase rules evaluation errors:

```text
✔ PRISM v3.0.0 Firestore Emulator Security Rules Suite
  ✔ A. Instructor Role Escalation Prevention (6 tests)
  ✔ B. Session Access Control (4 tests)
  ✔ C. Private Instructor Notes Isolation & Migration (6 tests)
  ✔ D. Student Practice Mode Permissions (4 tests)
  ✔ E. Additional Security Checks & Multi-Session Migration Compatibility (4 tests)
ℹ tests 24
ℹ suites 6
ℹ pass 24
ℹ fail 0
```

---

## 5. Troubleshooting

| Issue | Cause | Resolution |
|---|---|---|
| `Port 8080 is not open on localhost` | Another process or previous emulator instance is using TCP port `8080`. | Stop the existing process on port `8080` or update `emulators.firestore.port` in `firebase.json` and `test/firestore_rules/firestore_rules.test.mjs`. |
| `java: command not found` | Java Runtime is missing or not on `PATH`. | Install JDK 17+ and ensure `java -version` succeeds in your shell. |
| `First time running Firestore Emulator` | Firebase CLI needs to download the Firestore Emulator `.jar` binary on first run. | Allow the one-time download (`~/.cache/firebase/emulators/`) to complete with an active internet connection. |
| `Property <name> is undefined on object` | A rule accessed `data.<field>` or `request.auth.token.<claim>` directly when the property was absent. | Always use `.get('<field>', defaultValue)` in `firestore.rules` for optional fields and token claims. |

