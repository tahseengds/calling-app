# Firebase Phone Auth — One-Time Setup

The Flutter app now uses **Firebase Phone Auth** for SMS verification. Firebase
delivers the SMS and verifies the code; the app trades the resulting ID token at
`POST /api/auth/firebase-signin` for our own access + refresh JWTs.

Free tier: ~10 SMS / day — plenty for a private family app.

## Console (one-time, manual)

1. Open the existing Firebase project (the one whose `google-services.json` is
   already shipped in `flutter_app/android/app/`).
2. **Build → Authentication → Sign-in method → Phone → Enable**.
3. **Project settings → Your apps → Android app `com.lumin.app` → Add fingerprint**.
   - Debug SHA-1: `keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android`
   - Release SHA-1: from the keystore you sign release APKs with.
   - Phone Auth on Android uses Play Integrity (preferred) or SafetyNet
     (legacy) for app verification. Without the SHA-1 you'll get
     `app-not-authorized` errors at sign-in time.
4. Download a fresh `google-services.json` and replace
   `flutter_app/android/app/google-services.json`.
5. **(Optional) Add test phone numbers** under Authentication → Settings →
   Phone numbers for testing. These bypass real SMS delivery and accept a
   fixed code — useful for QA / CI without burning the daily SMS quota.

## Server (one-time, automated)

The service account JSON already shipped to `/opt/lumin/firebase-service-account.json`
for FCM is **enough** — our backend uses `google-auth`'s `verify_firebase_token`
to check ID-token signatures and only needs the matching `FIREBASE_PROJECT_ID`
in `.env`, which `deploy/setup_firebase.py` already writes.

Verify after deploy:

```bash
ssh root@lumin.tahseen.tech
docker exec lumin-fastapi-1 python -c \
  "from app.config import settings; print('project:', settings.FIREBASE_PROJECT_ID)"
# Expect: project: <your-firebase-project-id>
```

## Deploying the new code

1. From the project root:

   ```powershell
   set DEPLOY_PASSWORD=...
   python deploy/remote_deploy.py
   ```

   This rsyncs the backend tree to `/opt/lumin/` and `docker compose up -d`s.

2. Smoke-test:

   ```powershell
   curl https://lumin.tahseen.tech/health
   # {"status":"ok"}

   curl -X POST https://lumin.tahseen.tech/api/auth/firebase-signin \
     -H "Content-Type: application/json" \
     -d '{"firebase_id_token":"bogus","device_id":"smoke"}'
   # {"detail":"Invalid Firebase ID token","code":"unauthorized"}
   ```

   The 401 with `code: "unauthorized"` confirms the route is live and the
   verifier is wired correctly.

## Rolling back to the old register/login/verify-otp flow

The old endpoints are still mounted (marked `deprecated=True` in OpenAPI but
fully functional). To roll the Flutter app back, revert
`flutter_app/lib/features/auth/**` to the previous commit and rebuild —
nothing on the server changes.

## Cost expectations

- Firebase Phone Auth: free tier = 10 SMS / project / day, then $0.01–$0.06
  per verification depending on country. For a 10-user family that's
  effectively zero.
- A test phone number under the Authentication settings is free and skips SMS
  entirely.
- Test SMS aren't refunded if a user enters a wrong code — Firebase counts
  every send.

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `app-not-authorized` at `verifyPhoneNumber` | SHA-1 not added | Add debug/release SHA-1 to Firebase project, re-download `google-services.json` |
| `network-request-failed` | App can't reach `*.googleapis.com` | Check device internet; on emulators use `10.0.2.2` only for *our* backend, never for Firebase |
| `quota-exceeded` | Hit the 10 SMS/day cap | Use a test phone number for QA |
| Server returns `401 Invalid Firebase ID token` for a token that *should* be valid | Token older than 5 minutes (our replay window) | Have the client call `getIdToken(forceRefresh: true)` and retry immediately |
| Server returns `422 missing phone_number` | User signed in with email or Google instead of phone | Only the phone provider is supported |
