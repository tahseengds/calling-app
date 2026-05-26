# Deep links

The app handles `lumin://verify-email?oobCode=…` and
`https://lumin.tahseen.tech/auth/verify-email?oobCode=…` via the
`app_links` plugin. Both formats are produced by Firebase's email
verification flow (configured in `AuthNotifier._verifyEmailActionCodeSettings`).

## Android

Already wired in `android/app/src/main/AndroidManifest.xml`:

- `https://lumin.tahseen.tech/auth/*` with `autoVerify="true"` — Android
  App Link. **Until `assetlinks.json` is hosted (see below) Android will
  open the link in the browser**, not the app.
- `lumin://verify-email` — custom-scheme fallback. Firebase always sends
  an `https://` link, but this lets you trigger the flow from any other
  source (e.g. a test `adb shell am start` invocation).

## Publishing assetlinks.json (REQUIRED for the email link to open the app)

The template lives at `nginx/conf.d/assetlinks.json` and the nginx
location block is already in `nginx/conf.d/lumin.conf`. You just need to
fill in the SHA-256s and reload nginx.

### 1. Get the SHA-256 fingerprints

```powershell
cd flutter_app\android
.\gradlew signingReport
```

Scroll the output for two sections. Copy the `SHA-256` line from each:

- `Variant: debug` → debug fingerprint (so the flow works on
  `flutter run` / `flutter install`).
- `Variant: release` → release fingerprint (so the flow works on signed
  APKs going to users). If you haven't created a release keystore yet,
  this prints the debug one — that's fine, you can add the real release
  SHA-256 later without rebuilding the app.

### 2. Paste them into `nginx/conf.d/assetlinks.json`

Replace `REPLACE_WITH_DEBUG_SHA256` and `REPLACE_WITH_RELEASE_SHA256`
with the values from step 1. Keep the colons in the hex string.

### 3. Deploy

Deployment is SFTP-based via `deploy/remote_deploy.py` — there is no
`git pull` on the server. Run it from the project root:

```powershell
cd D:\calling-app
python deploy\remote_deploy.py
```

The script uploads `nginx/conf.d/assetlinks.json` and the updated
`nginx/conf.d/lumin.conf`, then does `docker compose up -d --build` +
an explicit `nginx` container restart — that's what reloads the
nginx config.

### 4. Verify the file is served correctly

```bash
curl -i https://lumin.tahseen.tech/.well-known/assetlinks.json
```

Expect HTTP 200, `Content-Type: application/json`, and your SHA-256s in
the body.

Also sanity-check from Google's tooling:
<https://developers.google.com/digital-asset-links/tools/generator>

### 5. Re-trigger Android's verifier

App Links are verified at install time. After publishing assetlinks.json
you need either a reinstall or a manual re-verification:

```bash
adb shell pm verify-app-links --re-verify com.lumin.app
adb shell pm get-app-links com.lumin.app
```

Look for `verified` (not `legacy_failure`) next to `lumin.tahseen.tech`.

Once that says verified, tapping the email link opens Lumio directly —
no chooser, no browser.

## iOS

The `ios/` directory doesn't exist in this checkout yet. When you add an
iOS target, drop this into `ios/Runner/Info.plist` inside the root
`<dict>`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.lumin.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>lumin</string>
        </array>
    </dict>
</array>
```

For Universal Links (the iOS equivalent of Android App Links — no
scheme prompt, opens the app directly):

1. Enable the **Associated Domains** capability in Xcode and add
   `applinks:lumin.tahseen.tech` to the entitlements.
2. Host an `apple-app-site-association` JSON at
   `https://lumin.tahseen.tech/.well-known/apple-app-site-association`
   (no extension, `Content-Type: application/json`):
   ```json
   {
     "applinks": {
       "details": [{
         "appIDs": ["TEAMID.com.lumin.app"],
         "components": [{"/": "/auth/*"}]
       }]
     }
   }
   ```

## Firebase Console

For the email link to route through this flow:

- **Authentication → Sign-in method**: Email/Password enabled.
- **Authentication → Settings → Authorized domains**: `lumin.tahseen.tech`
  added (the host in `ActionCodeSettings.url`).
- **Project Settings → Your apps → Android**: package name `com.lumin.app`
  with both debug and release SHA-1 / SHA-256 fingerprints.
- **Authentication → Templates → Email address verification**: optional
  branding (sender name, subject).
- **Do NOT** enable Dynamic Links — deprecated, and we don't depend on it.
