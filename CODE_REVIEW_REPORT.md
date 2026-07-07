# Code Review Report — Lumin (Lumio) Calling App

**Date:** 2026-07-07
**Scope:** Full-stack review — Flutter client (`flutter_app/`), FastAPI backend (`backend/api/`), Node.js signaling service (`backend/signaling/`), and infrastructure/deploy (`docker-compose*`, `nginx/`, `redis/`, `coturn/`, `deploy/`).
**Method:** Static review by five parallel subsystem reviewers; every reported finding was re-verified against current source. The backend test suite (73 tests) was run locally against a real Postgres + Redis as a baseline.

> This report supersedes the earlier `AUDIT_REPORT.md` (2026-05-27). Since that audit, **most of its 64 findings have been fixed** — see the "Prior-audit status" section. The issues below are the ones that are **still present in current code**, plus newly-discovered defects.

---

## Executive summary

The codebase is in materially better shape than the May audit: the broken hot-path import, the conversation/call N+1s, the pagination cursor bug, the removeContact id mismatch, the fake-OTP change-number flow, the dead attachment sheet, CORS `*`, the rate-limit IP bug, the `/api/users/{id}` PII leak, and ~40 other items are **resolved**.

What remains clusters into three themes:

1. **A remotely-triggerable signaling crash and a couple of process-killer paths** — the signaling server can be taken down by a single malformed socket event, and any Redis blip can crash it. (Highest operational risk.)
2. **Broken access-control on message reads and call logging** in the FastAPI backend — a handful of endpoints trust client-supplied IDs (`client_id`, `reply_to_id`, `call_id`, `peer_user_id`) without an ownership/relationship check, plus a health-report header-spoof and a stored-XSS vector on document uploads.
3. **A hard client-side lockout and a timezone bug in the Flutter app** — App Lock permanently bricks non-biometric devices, and every synced message renders in UTC. Plus several silent-failure paths (missed-call badge, offline outbox, read receipts, disappearing-message purge).

**A live production TURN secret and the production host IP are committed to the repo** — this is the single most urgent item and requires secret rotation, not just a code change.

### Counts of still-open issues

| Severity | Backend | Signaling | Flutter | Infra | Total |
|---|---|---|---|---|---|
| Critical | — | 1 | 1 | 1 | **3** |
| High | 3 | 3 | 1 | 2 | **9** |
| Medium | 3 | 4 | 5 | 4 | **16** |
| Low | 2 | 6 | 5 | 3 | **16** |

---

## CRITICAL

### C1 — Committed production TURN secret + host IP (infra)
- **Where:** `deploy/fix_turns_health.py:49` (hardcoded `TURN_SECRET=80c0816f…b134f6`); the same secret appears **16×** in the tracked transcript `docs/sessions/2026-05-25-session-a-firebase-phone-auth.jsonl`; production IP `165.227.146.247` is hardcoded across `deploy/*.py`.
- **Why it matters:** coturn uses `use-auth-secret` HMAC auth. Anyone with repo access can mint valid TURN credentials and use the relay as an open bandwidth proxy or relay/observe call media. `.gitignore` correctly excludes `.env`/`firebase-service-account.json`, but the "sanitized" session transcript leaked the secret that sanitization was supposed to strip.
- **Fix:** Rotate `TURN_SECRET` on the server; scrub the secret from the script (read from env) and from the transcript; treat the host IP/domain as non-secret but stop hardcoding it.

### C2 — Signaling server crashes on a single malformed `message:ack` (signaling)
- **Where:** `backend/signaling/src/messageHandler.js:96` — `socket.on('message:ack', ({ messageId }) => …)` destructures the payload directly.
- **Failure scenario:** Any authenticated client emits `message:ack` with no argument → `TypeError: Cannot destructure property 'messageId' of undefined` thrown synchronously in Socket.IO's dispatch. Socket.IO does not catch listener exceptions and no `uncaughtException` handler exists, so **the process exits, dropping every live call and socket for all users.** Docker restarts it; the attacker loops for a persistent outage. Every other handler uses the defensive `payload || {}` pattern — this one was missed.
- **Fix:** `socket.on('message:ack', (payload) => { const { messageId } = payload || {}; … })`, plus a global `unhandledRejection`/`uncaughtException` guard (see H-SIG-1).

### C3 — App Lock PIN fallback permanently locks out non-biometric devices (Flutter)
- **Where:** `flutter_app/lib/features/settings/ui/app_lock_gate.dart:127-132`, mounted in `app.dart:378` inside `MaterialApp.router`'s `builder`.
- **Failure scenario:** `AppLockGate` sits **above** the Router's `Navigator` (the builder's `child` *is* the router output). When biometrics are unavailable and a PIN is set, `_tryUnlock` calls `Navigator.of(context, rootNavigator: true).push(...)` — there is no Navigator ancestor, so it throws; `_locked` stays true and tapping "Unlock" repeats the crash. Even if a navigator were reachable, the pushed screen would render *under* the opaque lock overlay. Result: on any device without biometrics (or one that later loses biometric enrolment — the exact case the code's own comments anticipate), the app is **permanently inaccessible**. The setup path works (it pushes from a route context), so this survives casual testing.
- **Fix:** Render the PIN entry **inline inside the lock overlay** (in the `Stack` in `build`) instead of pushing a route.

---

## HIGH

### Backend

**H-BE-1 — Cross-conversation message disclosure via unvalidated `reply_to_id`.**
`backend/api/app/services/message_service.py:150` stores the request's `reply_to_id` and `_load_reply_preview` (`:98-110`) previews it with **no check that the quoted message is in the same conversation**. `build_reply_preview` (`conversation_service.py:47-55`) returns the quoted message's raw `content`. An attacker sends a normal message to their own contact but sets `reply_to_id` to a victim message's UUID in an unrelated conversation → the 201 response's `reply_to.text` (also published to the recipient's `msg_delivery` channel) contains that message's text. **Fix:** validate `reply_to.conversation_id == conv.id` at send time; reject otherwise.

**H-BE-2 — Message/media disclosure via `client_id` collision (IDOR).**
`message_service.py:141-173` inserts with `id=req.client_id` (client-chosen) `ON CONFLICT DO NOTHING`, then on conflict re-loads the row by that id and returns it **without verifying it belongs to the sender or the just-created conversation**. Posting a `client_id` equal to a foreign message's UUID returns that message's `content`, a freshly-minted signed media URL, `sender_id`, and `conversation_id`. Exploit requires guessing a random v4 UUID (limits reach), but it is a real authorization gap. **Fix:** on the conflict path, assert `msg.sender_id == sender.id and msg.conversation_id == conv.id`; else raise `ConflictError`.

**H-BE-3 — Detailed `/health` report reachable externally via spoofed `X-Real-IP`.**
`main.py:128-164` (`_is_internal` → `client_ip`) trusts the `X-Real-IP` request header, but the nginx `location = /health` block (`nginx/conf.d/lumin.conf:51-55`) sets only `Host` — it does **not** override `X-Real-IP` (the `/api/` block does). `GET /health?detailed=true` with header `X-Real-IP: 127.0.0.1` from anywhere returns the full topology/environment report (`domain`, `turn_host`, `postgres_db`, `redis_host`, `app_env`, `debug`, signaling/Firebase wiring). **Fix:** set `proxy_set_header X-Real-IP $remote_addr;` (and `X-Forwarded-For`) in the `/health` block.

### Signaling

**H-SIG-1 — Unhandled promise rejection on any Redis error kills the process.**
`callHandler.js:152,297,331,347,360,410,469` and `server.js:69-73` (`onPing`) `await` Redis calls **outside** their try/catch. A brief Redis unavailability rejects the promise; Node ≥15 terminates on `unhandledRejection` and no handler is registered anywhere. `call:ice` fires many times/sec during setup and `onPing` fires on every engine.io ping, so a 2-second Redis blip during any active call near-certainly crashes the whole signaling server. **Fix:** add `process.on('unhandledRejection')` + `process.on('uncaughtException')` logging guards, and wrap the bare awaits.

**H-SIG-2 — Signaling ignores token revocation; logout doesn't cut off socket access.**
`auth.js:12-23` verifies signature/expiry only. FastAPI mints access tokens with a `jti` and rejects revoked ones via `token_revoked:{jti}` in Redis (`dependencies.py:72-74`); the signaling server never checks it. A logged-out (revoked) token still connects to `/signal`, and because the socket TTL is refreshed on every ping (`server.js:71`), an open socket outlives token expiry indefinitely. **Fix:** in the `io.use` handshake, `EXISTS token_revoked:{jti}` and reject if present.

**H-SIG-3 — Block enforcement on `call:initiate` is one-directional.**
`callHandler.js:131-144` + `db.js:29-35` check only the **caller's** contact rows (`WHERE user_id = caller AND is_blocked = false`). FastAPI checks both directions for messaging (`message_service.py:79-95`). So if Alice blocks Bob, Bob's own row for Alice is untouched and Bob can still ring Alice (5 calls/min) — exactly what blocking should prevent. **Fix:** add a reverse-block lookup (recipient blocked caller) before allowing the call.

### Flutter

**H-FL-1 — Every synced message displays in UTC, not local time.**
`shared/models/message.dart:256` parses `created_at` with `DateTime.parse(...)` and **no `.toLocal()`**, while sibling code converts (`conversation_repository.dart:36`, `sync_service.dart:123,139`). `_Timestamp` then formats the UTC instant. On any non-UTC device every synced bubble shows the wrong wall-clock time; call-log rows in the same screen *do* convert (`chat_rich_screen.dart:2584`), so the two disagree, and optimistic just-sent messages (local time) visibly "jump" when the server copy replaces them. Same root cause skews date separators / "Today"/"Yesterday" grouping (`chat_rich_screen.dart:1403-1407`) and call-history dates (`call_record.dart:32`). **Fix:** append `.toLocal()` in `message.dart` and `call_record.dart`.

**H-FL-2 — Quality sampler can resurrect an ended call and wedge the calling stack.**
`call_notifier.dart:1041-1051`: `_sampleQuality` captures `session`, `await`s `_webrtc!.getStats()`, then writes `state = session.copyWith(...)` with **no post-await liveness re-check**. If the peer hangs up mid-poll, state goes `connected → ended → connected(stale)`; the 2 s cleanup sees `connected`, never nulls the session, and thereafter `startCall` returns "one active call at a time" and every incoming call auto-rejects with `call:busy` until app restart. **Fix:** re-read `state` after the await; bail if no longer active and apply `copyWith` to the current state.

### Infra

**H-INF-1 — Both app containers run as root.** `backend/api/Dockerfile` and `backend/signaling/Dockerfile` define no `USER`. The FastAPI image shells out to `ffmpeg` on user-uploaded video; an RCE there runs as UID 0 in-container. **Fix:** add a non-root `USER`.

**H-INF-2 — Production nginx serves without the hardening headers.** The mounted `nginx/conf.d/lumin.conf` has only HSTS (`:33`); it is missing `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`. The hardened `ssl.conf.template` has them but only overwrites `lumin.conf` on first cert issuance, so the weaker committed config is what actually runs. **Fix:** add the headers to `lumin.conf`.

---

## MEDIUM

### Backend
- **M-BE-1 — `log_call` trusts client `peer_user_id`/`call_id` with no contact/ownership check** (`call_service.py:42-76`). An attacker can pre-insert a `call_id` to pre-empt the signaling server's real record (`ON CONFLICT DO NOTHING` makes the genuine row a silent no-op) or fabricate history rows against any user. **Fix:** verify `peer_user_id` is a contact before persisting.
- **M-BE-2 — Stored-XSS via document upload** (`media_service.py:357-367`). `process_document` keeps the client-supplied extension; a libmagic-detected `text/plain` file can be stored as `documents/{uuid}.html` and nginx serves `/media/` by extension with no `Content-Disposition: attachment`/`nosniff`, so `<script>` runs on the app origin. **Fix:** force a safe stored extension, and add `X-Content-Type-Options: nosniff` + `Content-Disposition: attachment` on `/media/`.
- **M-BE-3 — `validate_upload` buffers the whole file in memory** (`media_service.py:120-135`). A 150 MB video is held (multiply-copied) in RAM; a few concurrent large uploads can OOM the single worker. **Fix (deferred, larger):** stream chunks to a temp file; pass a `Path` to processors.

### Signaling
- **M-SIG-1 — `typing:start/stop` deliver to any UUID with no contact/block check** (`typingHandler.js:11-46`). A blocked user can push perpetual "typing…" to their victim at 60/min. **Fix:** gate on `getContactUserIds` like `call:initiate`.
- **M-SIG-2 — `presence:get` returns presence/last-seen for arbitrary user IDs** (`presenceHandler.js:59-87`), no relationship check, up to 100 IDs × 30/min. A blocked/removed user can still track online transitions and exact last-seen. **Fix:** filter requested IDs to the caller's contacts.
- **M-SIG-3 — Disconnect handler clobbers a newer connection's session (reconnect race)** (`server.js:101-125`). On a network flap the stale socket's disconnect `DEL`s `socket_sessions:{userId}` and marks the (already-reconnected) user offline. **Fix:** only clear if the stored socket id still equals this socket's id.
- **M-SIG-4 — Ring-timeout timer races `call:answer`** (`callHandler.js:233-278` vs `309-317`). An answer arriving as the 45 s timer fires can produce contradictory `call:missed`+`call:answered`, delete the live session, and record a "missed" call for a connected one. **Fix (deferred, needs care):** re-check session state inside the timer after re-loading, and make answer/timeout mutually exclusive via an atomic state flip.

### Flutter
- **M-FL-1 — Missed-calls badge never fires** (`missed_calls_badge.dart:57`). It filters `status == 'missed'` but the only writer stores `'${direction}_${status}'` → `'incoming_missed'` (`call_repository.dart:111-113`). The badge is always 0. **Fix:** filter `status == 'incoming_missed'`.
- **M-FL-2 — Sync converter drops `expiresAt`/`editedAt`/`pinnedAt`/`durationSeconds`** (`sync_service.dart:167-182` vs the complete `message_local_dao.dart:152-173`). A **disappearing message** received while offline is stored with `expiresAt = NULL` and never purged — it persists forever, defeating the feature. **Fix:** reuse the DAO's complete converter.
- **M-FL-3 — Read receipts never sent for synced messages** (`chat_notifier.dart:211-223,249-258`; `sync_service.dart:81-96`). Messages inserted by `fetchMissedMessages` are shown via the Drift watch but no `PUT /api/messages/read` is issued, so the sender stays on "delivered" forever. **Fix:** after sync completes, mark the newly-synced unread messages read.
- **M-FL-4 — Token refresh hard-recycles the signaling socket** (`signaling_service.dart:246-279`); the purpose-built `updateToken()` (`:763-779`) has zero callers. On the ~hourly 401 refresh the socket is disposed/re-handshaked and a `call:hangup`/`call:ice` in that window is lost. **Fix (deferred):** wire `updateToken()` into the auth-token listener for same-session rotation.
- **M-FL-5 — `chatProvider` family is not `autoDispose`** (`chat_notifier.dart:902-903`); every opened conversation permanently leaks 10 stream subscriptions, a 20 s purge `Timer.periodic`, and a Drift watch. **Fix (deferred, needs dispose audit):** make it `autoDispose` and confirm `onDispose` teardown.

### Infra
- **M-INF-1 — Redis has no auth/`protected-mode`/`bind`** (`redis/redis.conf`), and dev compose publishes `6379`/`5432` to the host. **Fix:** set `requirepass`, `protected-mode yes`; drop host port publishing where not needed.
- **M-INF-2 — Deploy scripts use `AutoAddPolicy` (no SSH host-key verification)** and default `USER=root` (`deploy/remote_deploy.py:110` et al.). MITM on the SSH path is undetected. **Fix:** pin known host keys.
- **M-INF-3 — FastAPI/worker containers have `restart: always` but no healthcheck** (`docker-compose.yml:36,52`); a hung-but-alive process is never recycled. No resource limits anywhere. **Fix:** add healthchecks and `mem_limit`/`cpus`.
- **M-INF-4 — DH-params hardening is `docker cp`-ed at runtime and lost on rebuild** (`deploy/dh-and-headers.sh:48`), which then breaks `nginx -t`. **Fix:** bake dhparam into the image/config.

---

## LOW (selected)

- **L-BE-1 — `rate_limit` can leave a TTL-less bucket** if the process dies between `INCR` and `EXPIRE` (`dependencies.py:129-131`) → permanent rate-limit for that IP+endpoint. Use an atomic `SET NX PX`/Lua.
- **L-BE-2 — Firebase email-based account linking** back-fills `firebase_uid` by matching email (`auth_service.py:69-106`); safe only while every provider guarantees `email_verified`. Add an explicit assertion.
- **L-SIG-1 — `call_id` collision check is TOCTOU** (`callHandler.js:152-174`); use `SET … NX`.
- **L-SIG-2 — SDP object form has no size cap** (`callHandler.js:34-40`); a 1 MB `offer.sdp` is fanned out and copied into the FCM queue.
- **L-SIG-3 — Non-`/health` HTTP requests hang open** until `requestTimeout` (`server.js:24-30`); 404-and-end instead.
- **L-SIG-4 — One corrupt `user_presence` value makes `presence:get` return nothing** (`presenceHandler.js:77-87`); per-entry try/catch.
- **L-SIG-5 — Signaling container runs as root** (`backend/signaling/Dockerfile`).
- **L-FL-1 — `syncPendingMessages` retries permanently-rejected (4xx) messages forever** (`sync_service.dart:71-73`); mark 4xx rows `failed`.
- **L-FL-2 — `TokenInterceptor._replay` leaks a `_retry` marker as a real HTTP header** and drops request `extra`/timeouts (`token_interceptor.dart:97-122`).
- **L-FL-3 — App Lock PIN screen caps input at 6 digits while promising "4–8"** (`app_lock_pin_screen.dart:27,116`).
- **L-FL-4 — `FlButton.loadingLabel` is dead code** — loading labels never render (`fl_button.dart:57-66`).
- **L-FL-5 — Forward-media success snackbar shows even on failure** (`chat_rich_screen.dart:1612-1621`, `chat_notifier.dart:713-735`) — silent data loss with a false "Forwarded" confirmation.
- **L-INF-1 — `init.sql` + Alembic 0001 both create the schema**; only `init.sql` uses `IF NOT EXISTS`, so `alembic upgrade head` on a fresh init.sql-populated DB can hit "relation already exists".

---

## Prior-audit status (AUDIT_REPORT.md, 2026-05-27)

Verified fixed since the last audit (spot-checked in current code):

- Broken `from sqlalchemy import in_` in `message_service.py` — **fixed**.
- Conversation-list N+1 and call-history N+1 — **fixed** (both batch with `IN` queries).
- `/api/users/{user_id}` PII exposure — **fixed** (now requires a `Contact` row or self).
- CORS `allow_origins=["*"]` — **fixed** (restricted to the configured domain).
- Rate-limit using raw `request.client.host` — **fixed** (`client_ip()` reads `X-Real-IP`).
- Deprecated phone-auth routes, `UpdateProfileRequest` phone drop — **fixed** (phone removed entirely, migration `0004`).
- Audio upload size limit, `auth_service.logout` broad except, `decode_cursor` swallowing — **fixed**.
- All signaling authz items (`call:initiate`/`ice`/`answer`/`busy` participant gating, rate limiting, `presence:get` MGET, packet-listener leak) — **fixed** (except the residual one-directional block check H-SIG-3 and missing revocation check H-SIG-2).
- Flutter: removeContact id, pagination cursor, fake-OTP change-number (removed), dead attachment sheet, emoji picker, `state.otherUser!` guard, `getCall` phantom route, `print()`, ICE `catch(_){}`, cached images + client-side compression, tap-to-unfocus, pull-to-refresh, mic-permission feedback — **all fixed**.

Two baseline test observations: `tests/test_media.py` requires `ffmpeg` on the host (passes once installed); `tests/test_reactions.py::test_cannot_react_to_deleted_message` asserts HTTP 400 but the app raises `ValidationFailedError` (422) — the app is internally consistent (422 is its validation-failure code everywhere), so the **test is stale**, not the code.
