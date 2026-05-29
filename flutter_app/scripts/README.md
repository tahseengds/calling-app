# Release scripts

## `distribute` — build & push a release to Firebase App Distribution

Builds the **release** Flutter app (production endpoints by default) and uploads
it to Firebase App Distribution via the Firebase CLI.

### One-time setup

```bash
npm install -g firebase-tools   # install the Firebase CLI
firebase login                  # authenticate (persists on your machine)
```

You also need `android/app/google-services.json` in place — the script reads the
Firebase **App ID** from it automatically (override with `-AppId` / `-a` or
`FIREBASE_APP_ID` if you prefer).

> Make sure the testers / tester **group** exist in the Firebase console under
> *App Distribution → Testers & Groups*. The default group is `testers`.

### Run it

**Windows (PowerShell)** — from the `flutter_app` directory:

```powershell
.\scripts\distribute.ps1
```

If PowerShell blocks the script, run it once as:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\distribute.ps1
```

**macOS / Linux / CI:**

```bash
./scripts/distribute.sh
```

### Common options

| PowerShell            | Bash    | Meaning                                            |
|-----------------------|---------|----------------------------------------------------|
| `-Groups "qa,beta"`   | `-g`    | Tester groups (comma-separated). Default `testers`. |
| `-Testers "a@b.com"`  | `-t`    | Individual tester emails.                          |
| `-Notes "..."`        | `-n`    | Release notes. Default: `v<version> - <sha> - <date>`. |
| `-Aab`                | `-b`    | Build an `.aab` instead of an `.apk`.              |
| `-AppId "1:..:.."`    | `-a`    | Override the Firebase App ID.                      |
| `-NoBuild`            | `-N`    | Skip building; upload the most recent artifact.    |

Examples:

```powershell
.\scripts\distribute.ps1 -Groups "qa,internal" -Notes "Fixes call crash"
.\scripts\distribute.ps1 -NoBuild        # re-upload the last build, no rebuild
```

### CI / non-interactive auth

Instead of `firebase login`, set one of:

- `FIREBASE_TOKEN` — a CI token (`firebase login:ci`), or
- `GOOGLE_APPLICATION_CREDENTIALS` — path to a service-account JSON granted the
  **Firebase App Distribution Admin** role.
