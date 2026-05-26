# Claude Code Session Transcripts

Raw JSONL transcripts from the Claude Code harness, captured during major
development sessions. Useful as an audit trail of the design conversations
and diagnostic steps that produced each commit.

## Files

| File | Date | Topic |
|---|---|---|
| `2026-05-25-session-a-firebase-phone-auth.jsonl` | 2026-05-25 | Firebase Phone Auth migration; Prompt-14 WebRTC layer; Prompt-15 native call service; Windows AF_UNIX Gradle workaround |
| `2026-05-25-session-b-fcm-branding.jsonl` | 2026-05-25 | FCM token registration wiring (closes the killed-app push loop); branding refresh (launcher icon, splash, in-app logo); coturn TURNS port enablement |

## Sanitization

All transcripts are **pre-sanitized** before commit. The following patterns
are replaced with `[REDACTED_*]` placeholders:

| Pattern | Placeholder |
|---|---|
| Firebase Web API keys (`AIzaSy…`) | `[REDACTED_FIREBASE_API_KEY]` |
| JWT triple-segment tokens (`eyJ…eyJ…`) | `[REDACTED_JWT]` |
| Pakistan E.164 phone numbers (`+92…`) | `[REDACTED_PHONE_PK]` |
| US E.164 phone numbers (`+1…`) | `[REDACTED_PHONE_US]` |
| `Bearer <token>` headers | `Bearer [REDACTED]` |
| `TURN_SECRET=…` env-var lines | `TURN_SECRET=[REDACTED]` |
| VPS IP `165.227.146.247` | `[REDACTED_VPS_IP]` |

**Never commit raw `.jsonl` exports** — they live under
`C:\Users\<user>\.claude\projects\D--calling-app\<uuid>.jsonl` on the dev
box and will contain every tool result verbatim (including
`google-services.json` dumps, JWTs printed during diagnostics, etc.).
Use the sanitizer in `docs/sessions/sanitize.ps1` (or replicate the
regex pass from the README's history) before adding to git.

## Why save them at all

- **Diagnostic context** — when something breaks months later, the
  transcript shows the original investigation that produced the fix
  (e.g. why we set `org.gradle.java.home` to JBR, what triggered the
  307-redirect-strips-auth diagnosis, the BILLING_NOT_ENABLED Firebase
  quirk that drove our test-phone-number setup).
- **Decision archaeology** — major design choices (Firebase Phone Auth
  vs. self-hosted SMS, the dedup strategy for socket-vs-FCM call
  delivery, the AF_UNIX workaround scope) are reasoned out in these
  transcripts. The commit messages summarize the conclusions; the
  transcripts preserve the trade-offs.
- **Future Claude sessions** can grep these for prior context if you
  paste a relevant excerpt into a new conversation.
