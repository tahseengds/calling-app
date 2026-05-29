# Firebase (FCM) setup for Lumin

Push notifications need **three pieces**: a Firebase project, the **backend** service account, and the **Android app** config (`google-services.json`).

---

## Part 1 — Firebase Console (one-time)

### 1. Create or open a project

1. Go to [Firebase Console](https://console.firebase.google.com).
2. **Add project** (or use an existing one). Name it e.g. `lumin` or `tahseen-lumin`.

### 2. Note your Project ID

- **Project settings** (gear) → **General** → **Project ID**  
  Example: `lumin-abc123`  
  This becomes `FIREBASE_PROJECT_ID` in `.env`.

### 3. Enable Cloud Messaging API

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select the **same** project.
2. **APIs & Services** → **Library** → search **Firebase Cloud Messaging API**.
3. Click **Enable** (if not already enabled).

### 4. Create a service account key (backend)

1. Firebase Console → **Project settings** → **Service accounts**.
2. Click **Generate new private key** → confirm.
3. Save the downloaded JSON as:

   ```
   calling-app/firebase-service-account.json
   ```

   (This file is in `.gitignore` — never commit it.)

### 5. Register the Android app

1. Firebase Console → **Project overview** → **Add app** → **Android**.
2. **Android package name:** `com.lumin.app` (must match `applicationId` in the Flutter app).
3. Download **`google-services.json`**.
4. Place it at:

   ```
   flutter_app/android/app/google-services.json
   ```

5. Skip SHA-1 for now if you only test debug builds; add it later for release.

---

## Part 2 — Server (DigitalOcean)

On the VPS, the file must live at:

```
/opt/lumin/firebase-service-account.json
```

And `.env` must include:

```env
FIREBASE_PROJECT_ID=your-project-id-from-json
FIREBASE_SERVICE_ACCOUNT_PATH=/app/firebase-service-account.json
```

### Option A — automated script (from your PC)

After you have `firebase-service-account.json` locally:

```powershell
$env:DEPLOY_PASSWORD='your-root-password'
python deploy/setup_firebase.py path\to\firebase-service-account.json
```

This uploads the JSON, updates `.env` on the server, and restarts `fastapi` + `worker`.

### Option B — manual SSH

```bash
# On your PC — copy the key (use scp or paste via editor)
scp firebase-service-account.json root@165.227.146.247:/opt/lumin/

# On the server
nano /opt/lumin/.env
# Set FIREBASE_PROJECT_ID=... from the JSON "project_id" field

cd /opt/lumin
chmod 600 firebase-service-account.json
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d fastapi worker
```

### Verify

Open **https://lumin.tahseen.tech/health** — **Firebase (FCM)** should show **ok**.

Or on the server:

```bash
docker exec lumin-fastapi-1 python -c "
from google.oauth2 import service_account
c = service_account.Credentials.from_service_account_file(
    '/app/firebase-service-account.json',
    scopes=['https://www.googleapis.com/auth/firebase.messaging'],
)
print('OK — project:', c.project_id)
"
```

---

## Part 3 — Flutter app (when you build the mobile app)

1. Add `google-services.json` (step 5 above).
2. Build a release APK — production endpoints are the default, so no flags
   are needed:

   ```bash
   flutter build apk --release
   # or, for per-ABI splits:
   flutter build apk --release --split-per-abi
   ```

   `flutter run` (debug) defaults to the local emulator host
   (`http://10.0.2.2:8000` / `ws://10.0.2.2:8001`). Override any endpoint
   explicitly when needed, e.g. to point a debug build at production:

   ```bash
   flutter run \
     --dart-define=API_BASE_URL=https://lumin.tahseen.tech \
     --dart-define=SIGNALING_URL=wss://lumin.tahseen.tech \
     --dart-define=APP_ENV=prod
   ```

3. The app must register its FCM token with the API (`POST /api/users/fcm-token`) after login — wire this in the Flutter app when you enable push on device.

---

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| Health: `missing /app/firebase-service-account.json` | File not on server or Docker volume not mounted — redeploy with `docker-compose.prod.yml` |
| Health: `FIREBASE_PROJECT_ID not set` | Update `/opt/lumin/.env` and restart containers |
| `403` / API not enabled | Enable **Firebase Cloud Messaging API** in Google Cloud |
| Pushes never arrive on phone | Add `google-services.json`, grant notification permission, register FCM token via API |
