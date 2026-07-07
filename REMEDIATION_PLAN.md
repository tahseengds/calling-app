# Remediation Plan — Lumin Code Review

Companion to `CODE_REVIEW_REPORT.md` (2026-07-07). This plan groups the open findings into phases, states the concrete change for each, and marks what is implemented in this pass versus deferred (with the reason). Priority order is: stop-the-bleeding operational/security → access-control → correctness/UX.

Legend: **[NOW]** implemented in this change · **[DEFER]** documented, left for a follow-up (reason given).

---

## Phase 0 — Secrets (must happen operationally, not just in code)

| ID | Change | Status |
|---|---|---|
| C1 | Remove the hardcoded `TURN_SECRET` from `deploy/fix_turns_health.py`; read it from the environment instead. Scrub the secret string from the tracked session transcript. | **[NOW]** (code + transcript) |
| C1-ops | Rotate `TURN_SECRET` on the production coturn server and restart it. | **[DEFER — operator action]**: requires server access; cannot be done from the repo. Called out explicitly in the report. |

## Phase 1 — Signaling stability & authz (highest operational risk)

| ID | Change | Status |
|---|---|---|
| C2 | Guard `message:ack` destructuring with `payload || {}`. | **[NOW]** |
| H-SIG-1 | Add `process.on('unhandledRejection')` + `process.on('uncaughtException')` logging handlers in `server.js` so a transient Redis error degrades instead of killing the process; wrap the bare `await`s in the call handlers. | **[NOW]** (global handlers + wrap the ping handler and the initiate `exists` check) |
| H-SIG-2 | In the `io.use` handshake, reject tokens whose `jti` is present in `token_revoked:{jti}`. | **[NOW]** |
| H-SIG-3 | Add a reverse-block check to `call:initiate` (recipient blocked caller). | **[NOW]** |
| M-SIG-1 | Gate `typing:start/stop` on the caller's non-blocked contacts. | **[NOW]** |
| M-SIG-2 | Filter `presence:get` requested IDs to the caller's contacts. | **[NOW]** |
| M-SIG-3 | Only clear `socket_sessions`/mark offline on disconnect if the stored socket id still matches. | **[NOW]** |
| M-SIG-4 | Ring-timeout vs answer race — re-check session state inside the timer. | **[DEFER]**: correct fix needs an atomic Redis state transition (Lua/`SET` with condition) to avoid introducing a new race; higher risk than the value at current scale (2-party family app). Documented. |
| L-SIG-* | TOCTOU `SET NX`, SDP size cap, 404 hanging requests, presence per-entry try/catch, non-root container. | **[NOW]** for the cheap/safe ones (SDP cap, `presence:get` per-entry guard, non-root `USER` in Dockerfile); **[DEFER]** for `SET NX` call-id (behavioral, low value). |

## Phase 2 — Backend access control

| ID | Change | Status |
|---|---|---|
| H-BE-1 | Validate `reply_to_id` belongs to the same conversation before storing/previewing. | **[NOW]** |
| H-BE-2 | On the `client_id` conflict path, assert the existing row is the sender's and in this conversation; else `ConflictError`. | **[NOW]** |
| H-BE-3 | Set `X-Real-IP`/`X-Forwarded-For` in the nginx `/health` block so `_is_internal` can't be spoofed. | **[NOW]** |
| M-BE-1 | `log_call` — verify `peer_user_id` is a contact before persisting. | **[NOW]** |
| M-BE-2 | Document upload stored-XSS — force a safe stored extension and add `X-Content-Type-Options: nosniff` + `Content-Disposition: attachment` on `/media/`. | **[NOW]** |
| M-BE-3 | Stream large uploads to disk instead of buffering in memory. | **[DEFER]**: touches `validate_upload` + all four media processors' signatures (bytes→Path); sizeable refactor with real regression surface. Documented as the largest backend follow-up. |
| L-BE-1 | Atomic rate-limit bucket (`SET NX PX`). | **[NOW]** (cheap, removes a lockout foot-gun) |
| L-BE-2 | Assert `email_verified` before email-based Firebase account linking. | **[NOW]** |

## Phase 3 — Flutter correctness & the lockout

| ID | Change | Status |
|---|---|---|
| C3 | App Lock: render PIN entry inline in the lock overlay instead of `Navigator.push`. | **[NOW]** |
| H-FL-1 | Add `.toLocal()` to `message.dart` and `call_record.dart` timestamp parsing. | **[NOW]** |
| H-FL-2 | Post-await liveness guard in `_sampleQuality`. | **[NOW]** |
| M-FL-1 | Missed-call badge: filter `'incoming_missed'`. | **[NOW]** |
| M-FL-2 | Use the complete DAO converter in `sync_service` so `expiresAt` et al. persist. | **[NOW]** |
| M-FL-3 | Send read receipts for messages inserted by sync. | **[NOW]** |
| L-FL-1 | Mark 4xx-rejected outbox rows `failed` instead of retrying forever. | **[NOW]** |
| L-FL-3 | Raise PIN `maxLength` to 8 to match the "4–8" copy. | **[NOW]** |
| L-FL-5 | Only show "Forwarded" after a successful forward. | **[NOW]** |
| M-FL-4 | Wire `updateToken()` for same-session token rotation. | **[DEFER]**: reconnect/lifecycle behavior is delicate; wrong handling risks dropped auth on the socket. Lower frequency (~hourly) than the value of getting it wrong. Documented. |
| M-FL-5 | Make `chatProvider` family `autoDispose`. | **[DEFER]**: requires verifying no screen holds a stale ref and that dispose teardown is race-free; a memory-growth issue, not a correctness bug, at family-app scale. Documented. |
| H-FL-A (data H1) | Convert `onReconnect` single slot to a listener registry and register SyncService globally. | **[DEFER]**: architectural change to reconnect wiring; needs an app-lifetime registration point and careful testing of offline replay. Highest-value deferred item — flagged for the next pass. |

## Phase 4 — Infra hardening

| ID | Change | Status |
|---|---|---|
| L-SIG-5 | Add non-root `USER` to the signaling Dockerfile. | **[NOW]** |
| H-INF-1 | Add non-root `USER` to the FastAPI Dockerfile. | **[DEFER]**: the API container writes user media to the `media_storage` volume. A non-root process cannot write an existing root-owned named volume, so shipping this unverified would break media uploads on the live deployment. Needs a coordinated volume `chown` (or an entrypoint that fixes ownership) validated against prod. The signaling container writes no volumes, so its non-root change ships now. |
| H-INF-2 | Add security headers to `nginx/conf.d/lumin.conf`. | **[NOW]** |
| M-INF-1 | Redis auth + host-exposure note. | **[NOW]** for documenting comments in `redis.conf`; **[DEFER]** the runtime change — `requirepass` needs a coordinated `.env`/client-URL change across FastAPI, signaling, and worker, and `protected-mode yes` **without** a password would reject those containers' non-loopback connections and break the app. Must be applied together, operator-coordinated. |
| M-INF-2/3/4, L-INF-1 | SSH host-key pinning, healthchecks/limits, dhparam baking, init.sql/alembic ordering. | **[DEFER]**: deploy-workflow changes best validated against the real host; out of scope for a code-only pass. Documented. |

## Test fixes

| ID | Change | Status |
|---|---|---|
| T1 | `tests/test_reactions.py::test_cannot_react_to_deleted_message` expects 400 but the app returns 422 (its consistent validation-failure code). Align the test to 422. | **[NOW]** |

---

## Verification strategy

- **Backend:** run the full pytest suite (Postgres + Redis + ffmpeg) before and after; it must stay green (73 passing). New authz branches get exercised by existing message/call tests; the reaction test fix is included.
- **Signaling:** `node --check` every changed file; `node -e "require(...)"` smoke-load; run the existing node tests if present.
- **Flutter:** no Flutter SDK in this environment, so changes are surgical and reviewed by hand — additive `.toLocal()`, a string-literal filter change, a post-await guard, an inline widget swap, and small null/branch guards. No API or signature changes that could ripple. Each change is called out in the commit for a maintainer to run `flutter analyze`/tests against.
- **Infra:** config-only; `nginx -t` semantics preserved (headers added inside existing `server`/`location` scope).

## Deferred items — summary rationale

Everything marked **[DEFER]** is either (a) an operator action the repo can't perform (secret rotation, prod SSH/redis-password coordination), (b) a refactor whose regression surface outweighs its value at this app's scale (upload streaming, ring-timeout atomic state, `chatProvider` autoDispose, socket token rotation), or (c) a deploy-workflow change that should be validated against the live host. The single highest-value deferred code item is the reconnect-registry fix (H-FL-A / data-layer H1), which silently breaks offline outbox replay for all but the last-opened chat; it is flagged as the top follow-up.
