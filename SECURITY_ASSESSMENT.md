# Security Assessment — Lumin (Lumio) Calling App

**Date:** 2026-07-07
**Scope:** Whole application — Flutter client, FastAPI backend, Node.js signaling service, and infrastructure (nginx, coturn, redis, Docker, deploy scripts).
**Method:** Adversarial security review across five attack surfaces (authentication/session, authorization/IDOR, injection/SSRF/XSS, secrets/crypto/transport, DoS/resource/infra), each finding re-verified against source. Tooling: `npm audit`, git-history secret scan, dependency review, and the backend test suite (75 tests) run against real Postgres + Redis.

> **No security review can prove an app is invulnerable to "all cyber attacks."** What this documents is a systematic audit of the classes that matter for this app, the issues found and fixed, and the residual risks with their remediation. It builds on the fixes in `CODE_REVIEW_REPORT.md` / `REMEDIATION_PLAN.md`.

---

## Overall posture: strong, with hardening applied

The app is **well-built defensively**. The audit found **no SQL injection, no command/argument injection, no path traversal, no SSRF via user input, no XSS, no confirmed authentication bypass, and no high-severity IDOR** in application logic. The token machinery, access-control scoping, media-signing, and TLS are all sound.

What existed were **denial-of-service / resource-exhaustion vectors, a dependency CVE, one infrastructure SSRF gap, and a set of hardening gaps** — most now fixed in this pass. The one item that cannot be fixed in code is the **TURN secret in git history, which must be rotated on the server**.

### What was fixed in this security pass

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | **High** | ffmpeg/ffprobe ran inline with **no timeout** — two crafted uploads could stall the whole API (2 workers) | Hard `asyncio.wait_for` timeout (60s) + kill on all ffmpeg/ffprobe calls; `-nostdin` (`media_service.py`) |
| 2 | **High** | `ws` 8.x memory-exhaustion DoS (GHSA-96hv-2xvq-fx4p) in the Socket.IO transport | `npm audit fix` → `ws` 8.21.0 (patched); engine.io/adapter bumped |
| 3 | **Medium** | coturn relay could reach `169.254.169.254` **cloud metadata** (SSRF/credential exfil) | Deny `169.254.0.0/16`, `100.64.0.0/10`, `0.0.0.0/8` (`turnserver.conf`) |
| 4 | **Medium** | Pillow decompression bomb — no pixel cap; a small file could decode to hundreds of MB | `Image.MAX_IMAGE_PIXELS = 40M` + explicit early reject (`media_service.py`) |
| 5 | **Medium** | Refresh-token rotation had no row lock → concurrent replay could fork sessions and evade reuse detection | Atomic conditional `UPDATE ... WHERE revoked_at IS NULL`; 0 rows → treated as replay (`auth_service.py`) |
| 6 | **Medium** | No rate limit on `/auth/refresh`, `/users/avatar`, `/support/feedback`, `/contacts` (add) — flood/enumeration | Added per-IP `rate_limit` deps (30/10/10/20 per 60s) |
| 7 | **Medium** | `SendMessageRequest.content` and `ReceiptRequest.message_ids` were unbounded (DB/Redis bloat; per-id query amplification) | `max_length=4000` on content; cap 500 ids (`schemas/message.py`) |
| 8 | **Medium** | No `JWT_SECRET` strength check — a weak env value silently weakened every token | Startup assert `len ≥ 32` in production (`config.py`) |
| 9 | **Medium** | Supply-chain: floating `*` pins on security-sensitive libs | Floors: `python-jose≥3.4.0`, `python-multipart≥0.0.7`, `Pillow≥10.3.0`, `jinja2≥3.1.4` |
| 10 | **Low** | `typing:stop` skipped the contact/block check `typing:start` had | Added `canInteract` gate (`typingHandler.js`) |
| 11 | **Low** | nginx running config weaker than the hardened template | OCSP stapling, `ssl_session_tickets off`, HSTS `preload`; `/api/` XFF set to `$remote_addr` |
| 12 | **Low** | `.gitignore` didn't cover key/cert files | Added `*.pem/*.key/*.p12/*.pfx/*.keystore/*.jks` |
| 13 | **Low** | Android had no explicit cleartext policy (relied on API-28 default) | `network_security_config.xml` — cleartext denied except dev loopback |
| 14 | **Low** | Health "Domain & TLS" check used `verify=False` (couldn't detect a bad cert) | `verify=True` (`health_service.py`) |

All 75 backend tests pass after these changes.

---

## MUST DO — operator action (cannot be fixed in code)

### 🔴 Rotate `TURN_SECRET` (Critical)
The production TURN shared secret (`80c0816f…b134f6`) was committed and **remains recoverable from git history** (`git show <old-commit>:deploy/fix_turns_health.py`), even though it's now scrubbed from the working tree. coturn uses HMAC auth, so anyone with repo/history access can mint valid TURN credentials and abuse the relay or observe call media paths.
- **Do:** generate a new secret (`openssl rand -hex 32`), update `.env` on the server (coturn **and** FastAPI must match), restart coturn + FastAPI.
- **Optional hygiene:** rewrite history (`git filter-repo`) to purge the old value, and drop the `!docs/sessions/*.jsonl` allowlist so raw transcripts stop being a leak channel.
- No other real secret (`JWT_SECRET`, `POSTGRES_PASSWORD`, `MEDIA_SECRET`, the Firebase service-account JSON) was ever committed — history contains only `CHANGE_ME_*` placeholders. Confirmed.

---

## Residual risks — recommended follow-ups (deferred, with reasons)

These are real but were **not** changed in this pass because they need environment coordination, carry regression risk I can't validate without a running deployment, or are larger refactors. Ranked by value.

1. **Live signaling sockets survive logout (Medium).** Logout blacklists the access `jti`, and the signaling handshake now rejects revoked tokens — but an **already-open** socket isn't force-disconnected. Fix: on logout, publish a Redis event that the signaling process consumes to `socket.disconnect(true)` matching sockets. (Feature work across two services.)
2. **FastAPI/worker containers run as root (Medium).** The ffmpeg/Pillow-facing surface runs as UID 0. Deferred because the container writes to the `media_storage` volume; a non-root switch needs a coordinated volume `chown` validated against the live volume (an existing root-owned volume would break media writes).
3. **No container resource limits (Medium).** Add `mem_limit`/`cpus`/`pids_limit` so a memory/CPU spike is contained to one container instead of the host. Compose change; validate against the 2-vCPU droplet.
4. **Redis `allkeys-lru` can evict `token_revoked:{jti}` (Medium).** Under memory pressure a revoked token could be un-revoked early. Not reachable at 256 MB / 10 users, but at scale isolate revocation keys in a `noeviction` logical DB (or raise `maxmemory`). Not flipping the policy blindly, since `volatile-lru` risks OOM write-failures if non-TTL keys fill memory.
5. **Media transcode/probe runs on the request path (Medium).** Even with the new timeout, `media_worker.py` already exists — moving processing off the request thread frees request workers/DB connections during transcode.
6. **Large uploads buffered fully in memory (Medium).** Bounded by size limits, but streaming video straight to a temp file avoids the transient heap spike.
7. **Media signed URLs are unrevocable 1-hour bearer capabilities (Low).** Only conversation participants ever receive one, but a leaked URL works for its TTL and the file isn't deleted on message delete. Consider binding the signature to the requesting user and/or a shorter TTL.
8. **Call-log injection (Low).** A user can persist a `call_records` row against a contact (already limited to contacts by an earlier fix). Full fix requires correlating with the signaling server's authoritative session.
9. **SSH `AutoAddPolicy` in deploy scripts (Low).** First-connection MITM risk at deploy time; pin known host keys.
10. **nginx edge `limit_req`/`limit_conn` (Low).** All throttling is app-level; an edge rate-limit zone adds a cheap first line against volumetric floods.
11. **`list_contacts` / `list_conversations` unpaginated (Low).** Fine at family-app scale; add a hard `LIMIT` if the data model is ever reused.
12. **Flutter TLS certificate pinning (Low/optional).** Trusts the system CA store; pinning would defeat a trusted-CA MITM. Optional for a calling app.
13. **Logout requires a still-valid access token (Low).** If the access token has expired, the refresh token isn't revoked; allow logout to authenticate via the refresh token alone. (Client auto-refreshes first, so impact is bounded.)

---

## What the audit verified as DONE RIGHT (do not regress)

**Authentication / tokens.** HS256 with pinned `algorithms=[...]` on both FastAPI and signaling (no `alg:none`/confusion); `exp` enforced; access-token `type` claim checked; refresh tokens are high-entropy (`secrets.token_urlsafe(48)`), **stored hashed**, rotated on every use, with **reuse detection that revokes all sessions**; `jti` revocation enforced at both the API and the signaling handshake; Firebase verification pins audience + `email_verified` (linking gated on it too); bcrypt cost 12 for the admin path; access token **in memory only**, refresh token in the OS keystore, no tokens logged.

**Authorization.** Messages/reactions/receipts/pins are participant- or owner-scoped; `reply_to_id` is scoped to the conversation and `client_id` collisions with a foreign message are rejected (both fixed earlier); `GET /api/users/{id}` 404s for non-contacts; contacts/settings are principal-scoped; the admin panel is gated (constant-time password compare, bcrypt account path, email allowlist) with no role to escalate; signaling events enforce contact/participant membership, reverse-block on calls, and contact-scoped presence.

**Injection / SSRF / XSS.** All SQL is parameterized (ORM + `$1..$N`); ffmpeg via `create_subprocess_exec` (no shell) with server-generated paths (no argument injection); media paths are server-generated UUIDs (no traversal) and HMAC-gated (constant-time, expiry-checked, secret-gated — no forgery); no server-side fetch of user URLs; Jinja autoescape on with no `|safe`; no `dangerouslySetInnerHTML` in the website; no `pickle`/`yaml.load`/`eval`; regexes are linear (no ReDoS).

**Transport / infra.** TLS 1.2/1.3 only, strong ciphers, full security-header set, `/media/` forced `attachment`+`nosniff`; CORS locked to the production origin; Postgres/Redis internal-only in prod with healthchecks; coturn uses time-limited HMAC auth with RFC-1918 denies and quotas; signaling has per-user rate limits, SDP/ICE size caps, and crash-guard handlers; logs are JSON-escaped with no secret/PII leakage; API docs disabled in prod; detailed `/health` gated to internal callers (header-spoof closed earlier).

---

## How to re-run the checks

```bash
# Backend tests (Postgres + Redis + ffmpeg required)
cd backend/api && pytest -q

# Signaling dependency audit
cd backend/signaling && npm audit --omit=dev

# Secret-in-history scan
git log -p --all | grep -niE 'secret|password|BEGIN .*PRIVATE'
```
