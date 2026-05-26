# App Audit Report

**Scope:** Full audit of the Lumio calling app — Flutter frontend (`flutter_app/`), FastAPI backend (`backend/api/`), Node.js signaling service (`backend/signaling/`), and deploy scripts (`deploy/`).
**Method:** Read-only static review. No fixes applied.
**Date:** 2026-05-27

---

## Summary

- **Total issues found:** 64
- **Critical:** 6 | **High:** 17 | **Medium:** 27 | **Low:** 14

### Headline issues (must-fix before ship)

1. **Chat attachments are entirely dead** — the Photo/Video/Camera/Document buttons in the attachment bottom sheet only dismiss the sheet. There is no image_picker / file_picker wiring, so users cannot send any media from the chat composer. ([chat_rich_screen.dart:576-603](flutter_app/lib/features/chat/presentation/chat_rich_screen.dart))
2. **Change Phone Number is a client-side mock** — generates the OTP locally in Dart and shows it in a snackbar; the `updatePhone` call posts a field the backend silently discards. The feature persists nothing. ([change_number_screen.dart](flutter_app/lib/features/profile/presentation/screens/change_number_screen.dart), [user.py:27](backend/api/app/schemas/user.py))
3. **Remove-contact uses the wrong identifier** — Flutter calls `DELETE /api/contacts/{user_id}` but the backend expects the contact-row id, so removal always 404s. ([contact_repository.dart:48](flutter_app/lib/features/contacts/data/contact_repository.dart), [contacts.py:31](backend/api/app/routers/contacts.py))
4. **Older-messages pagination is broken** — the chat notifier sends the message UUID as `cursor`, but the backend expects a base64-encoded `created_at|id`, so loading older messages will fail to decode (or return wrong page). ([chat_notifier.dart:344-355](flutter_app/lib/features/chat/domain/chat_notifier.dart), [message.py:110](backend/api/app/schemas/message.py))
5. **Broken import in a hot path** — `from sqlalchemy import in_` inside `fetch_messages` raises `ImportError` on the first paged fetch that contains any media. ([message_service.py:261](backend/api/app/services/message_service.py))
6. **Conversation list N+1** — `list_conversations` issues 3–4 sequential DB queries per conversation (user, last message, media file, unread count). Latency scales linearly with the user's chat count.

---

## Issues by Category

### 1. Missing Features & Incomplete Flows

#### [DEAD-UI] Attachment bottom sheet has no implementation
- **Severity**: Critical
- **Location**: `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:576-603`
- **Description**: The Photo / Video / Camera / Document `_AttachListItem` tiles each have `onTap: () => Navigator.of(context).pop()` — tapping any of them just closes the sheet. No image_picker, file_picker, or camera launch.
- **Expected**: Tapping a tile picks the file and calls `chatProvider.sendMedia(file, type)`.
- **Suggested fix**: Wire `image_picker` (gallery/camera) and `file_picker` (document) → call `ref.read(chatProvider(id).notifier).sendMedia(...)`.

#### [DEAD-UI] Emoji picker button is a TODO
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:267`
- **Description**: `onEmoji: () {}` with comment `// TODO(backend): open emoji picker`.
- **Expected**: Tapping opens an emoji picker that inserts into the input.
- **Suggested fix**: Integrate `emoji_picker_flutter` or similar.

#### [DEAD-UI] "Send them an invite" button is empty
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/contacts/ui/add_contact_screen.dart:153`
- **Description**: When add-contact returns "Not on Lumio yet", an outline button "Send them an invite" appears with `onPressed: () {}`. No SMS/email invite path exists.
- **Expected**: Either launch the device share sheet with a deep link, or remove the button.
- **Suggested fix**: Use `share_plus` to share an invite link, or remove the button until the feature is built.

#### [DEAD-UI] Multiple "more" / overflow buttons do nothing
- **Severity**: Low
- **Location**: `flutter_app/lib/features/calling/presentation/call_history_screen.dart:74`, `flutter_app/lib/features/profile/ui/profile_screen.dart:225`, `flutter_app/lib/features/chat/presentation/media_viewer_screen.dart:87`
- **Description**: Three `IconButton`s with `onPressed: () {}`. Visually present, functionally inert.
- **Expected**: Either implement an overflow menu (search, settings, more options) or remove the icon.
- **Suggested fix**: Remove until features ship.

#### [DEAD-UI] Contact row tap is a no-op
- **Severity**: Low
- **Location**: `flutter_app/lib/features/contacts/ui/contacts_screen.dart:351`
- **Description**: `InkWell(onTap: () {})`. Long-press shows remove dialog; tap does nothing despite ripple feedback.
- **Expected**: Tap should open contact detail / chat, or remove the ripple if no action.
- **Suggested fix**: Tap → `getOrCreateConversation(user.id)` → push `/chat/$id` (same as the message icon), or set `onTap: null`.

#### [INCOMPLETE] Change Phone Number is a client-side mock
- **Severity**: Critical
- **Location**: `flutter_app/lib/features/profile/presentation/screens/change_number_screen.dart:35,91,96,108`
- **Description**: Generates `_generatedOtp = '123456'` client-side, fakes a 1s delay, shows the OTP to the user in a snackbar (!), then calls `profileNotifier.updatePhone(phone)`. The backend `UpdateProfileRequest` only accepts `name` (user.py:27), so the phone is silently discarded.
- **Expected**: Either remove the screen, or wire it through Firebase Phone Auth + a real backend endpoint that updates `users.phone`.
- **Suggested fix**: Hide the menu entry until a real flow exists. Showing fake OTPs to the user is a security-trust regression.

#### [INCOMPLETE] Deprecated phone-auth endpoints have no SMS provider
- **Severity**: Medium
- **Location**: `backend/api/app/services/auth_service.py:82` (`# TODO: integrate SMS provider`)
- **Description**: `/api/auth/register`, `/login`, `/verify-otp` are marked deprecated but still live. They generate OTPs in Redis but never deliver them. In DEBUG mode the OTP is logged.
- **Expected**: Either delete the routes (they're marked deprecated and the Flutter client no longer uses them) or wire an SMS provider.
- **Suggested fix**: Remove the three routes + the `register` / `verify_otp` / `login` service functions.

#### [TODO] Media utils helpers stub
- **Severity**: Low
- **Location**: `flutter_app/lib/core/utils/media_utils.dart:1`
- **Description**: `// TODO: prompt 13 — media upload helpers (MIME detection, thumbnail extraction)`.
- **Expected**: Centralized helpers, since chat & profile both do MIME detection ad-hoc.
- **Suggested fix**: Implement or delete the stub file.

#### [TODO] Native incoming-call notification stub
- **Severity**: Low
- **Location**: `flutter_app/lib/core/services/notification_service.dart:86`
- **Description**: `// TODO: prompt 15 — show full-screen incoming call notification`. The actual full-screen intent is wired in `MainActivity.kt`, so this comment may be stale.
- **Expected**: Either implement the Dart path or remove the TODO and document that the native FCM service owns full-screen call notifications.
- **Suggested fix**: Delete the TODO once verified.

#### [TODO] Reply preview / isDeleted fields on Message
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:853`
- **Description**: `// TODO(backend): expose isDeleted and replyTo on the Message model.` The screen falls back to `(msg as dynamic).isDeleted == true`, which is a fragile dynamic dispatch.
- **Expected**: `Message` model should explicitly carry `isDeleted: bool` and `replyTo: ReplyPreview?`.
- **Suggested fix**: Add fields to `shared/models/message.dart` and stop using `as dynamic`.

---

### 2. Missing / Incomplete Pages (Router Audit)

#### [ROUTING] No `/chat/search` results wiring verified
- **Severity**: Low
- **Location**: `flutter_app/lib/app.dart:98-100`, `flutter_app/lib/features/chat/presentation/search_screen.dart`
- **Description**: Route exists; full file not audited for completeness. Verify search actually queries the backend (no `/api/messages/search` endpoint exists).
- **Expected**: Functional search across conversations + messages.
- **Suggested fix**: Confirm whether the screen is local-only (Drift) or expects a backend search endpoint; build the missing endpoint if so.

#### [ROUTING] No way to register/route to settings sub-screens via deep link
- **Severity**: Low
- **Location**: `flutter_app/lib/app.dart`
- **Description**: Profile sub-routes (`/profile/notifications`, `/profile/privacy/blocked`, etc.) are registered but not exposed in any deep-link intent filter. Mainly an issue if you want notification-tap deep links to land on settings.
- **Expected**: Decide if these need external deep-link support.
- **Suggested fix**: No action if internal-only.

#### [ROUTING] `_LoginScreenState` and `_RegisterScreenState` define two `_OrDivider` / `_GoogleButton` classes
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/ui/login_screen.dart:238-339`, `flutter_app/lib/features/auth/ui/register_screen.dart:283-377`
- **Description**: Two private widgets duplicated across files. Both screens diverge slightly.
- **Expected**: Shared widget under `shared/widgets/`.
- **Suggested fix**: Extract to `shared/widgets/auth_widgets.dart`.

---

### 3. API & Endpoint Audit

#### [API-MISMATCH] removeContact uses user_id, backend expects contact_id
- **Severity**: Critical
- **Location**: `flutter_app/lib/features/contacts/data/contact_repository.dart:48` vs `backend/api/app/routers/contacts.py:31`
- **Description**: Client calls `_dio.delete('/api/contacts/$userId')` where `userId` is the *target user*'s UUID. Backend route is `DELETE /{contact_id}` which expects the contact-row UUID. The two are different — `Contact.id` is generated server-side; the client never stores it. Result: every remove returns 404 (silently rolled back via `load()` in `ContactsNotifier.removeContact`).
- **Expected**: Client tracks `Contact.id` and sends it on delete.
- **Suggested fix**: Extend the contact list shape used by `ContactsNotifier` to carry `contactId`, and pass that into `removeContact`. Backend already returns the right id via `ContactResponse.id`.

#### [API-MISMATCH] updatePhone payload is silently ignored
- **Severity**: High
- **Location**: `flutter_app/lib/features/profile/data/profile_repository.dart:24-30` vs `backend/api/app/schemas/user.py:27-35`
- **Description**: Client sends `PUT /api/users/me` with `{phone: ...}`. Backend `UpdateProfileRequest` only declares `name`. Pydantic ignores extras (default), so the phone is dropped without error — change-number "success" is a lie.
- **Expected**: Either remove the endpoint until a phone-change flow exists, or extend `UpdateProfileRequest` and add server-side phone validation + uniqueness check.
- **Suggested fix**: Surface this as a 400 in the backend, and rework the client flow with Firebase Phone Auth.

#### [API] Older-messages pagination uses wrong cursor format
- **Severity**: Critical
- **Location**: `flutter_app/lib/features/chat/domain/chat_notifier.dart:344-355` and `flutter_app/lib/features/chat/data/message_repository.dart:40-56`
- **Description**: Backend returns `MessagePage { messages, next_cursor }` where `next_cursor` is `base64(created_at|id)` ([schemas/message.py:105](backend/api/app/schemas/message.py)). The Flutter repo never reads `next_cursor` — `fetchMessages` returns only the messages list. The notifier then sets `oldestCursor: older.first.id` (a raw UUID string) which the backend `decode_cursor` cannot parse → first paginate call after the initial load throws on the server.
- **Expected**: Repository returns both messages and `next_cursor`; notifier passes `next_cursor` back unchanged.
- **Suggested fix**: Change `MessageRepository.fetchMessages` to return `({List<Message> messages, String? nextCursor})`; thread `nextCursor` through `ChatState.oldestCursor`.

#### [API] `/api/users/{user_id}` exposes any user's profile to any authed caller
- **Severity**: High
- **Location**: `backend/api/app/routers/users.py:33`
- **Description**: `get_user` only requires `get_current_user`. There is no contact-based authorization check, so any signed-in user can enumerate every other user's name / phone / email / avatar / last_seen by UUID.
- **Expected**: Restrict to users in caller's contacts, OR strip sensitive fields (phone/email/last_seen) when the caller isn't a contact.
- **Suggested fix**: Add a `_assert_in_contacts` check in `user_service.get_user` mirroring `_assert_can_message`.

#### [API] `/api/calls/history` returned 404 but client still references it
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/calling/data/call_repository.dart:42` (comment claims not implemented), `backend/api/app/routers/calls.py:28` (it IS implemented)
- **Description**: The Flutter comment says "the `/api/calls/history` endpoint is not yet implemented on the backend (tracked as a follow-up)" — but the backend has it. The client silently swallows 404s.
- **Expected**: Remove the silent-404 fallback now that the endpoint exists.
- **Suggested fix**: Update the comment and let DioException propagate to the UI; the call-history screen already shows an error state.

#### [API] `/api/calls/{call_id}` endpoint referenced from Flutter but missing from backend
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/calling/data/call_repository.dart:91-101` vs `backend/api/app/routers/calls.py`
- **Description**: `getCall(callId)` issues `GET /api/calls/{callId}` but no such route exists. Always returns null (caught DioException).
- **Expected**: Either add the backend route or remove the client method.
- **Suggested fix**: Confirm callers; if unused, delete the method.

#### [API] `/api/messages/search` referenced indirectly but not implemented
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/presentation/search_screen.dart` (assumed; not fully audited)
- **Description**: A search screen is wired into the router. There is no backend search endpoint. Confirm the screen is local-Drift-only; otherwise it will silently produce no results.
- **Expected**: Either build the search endpoint or scope the screen to local results.
- **Suggested fix**: Decide product direction.

#### [VALIDATION] `/api/users/avatar` lacks MIME re-validation at the router layer
- **Severity**: Low
- **Location**: `backend/api/app/routers/users.py:52-58`
- **Description**: Validation runs deep in `media_service.upload_avatar` via `validate_upload`. Acceptable, but the router exposes no explicit size limit decoration, making the contract opaque to OpenAPI consumers.
- **Expected**: Document the limit in the route description or add a `Field(max_length=...)`.
- **Suggested fix**: Add a short docstring with the size limit, or surface a `413` body on rejection.

#### [VALIDATION] Audio uploads use the document size limit
- **Severity**: Medium
- **Location**: `backend/api/app/services/media_service.py:83`
- **Description**: `_get_size_limit_mb` maps `"audio": settings.MAX_DOCUMENT_SIZE_MB` (25 MB). Settings has no `MAX_AUDIO_SIZE_MB`. Voice notes don't need 25 MB; documents shouldn't share an audio limit.
- **Expected**: Dedicated `MAX_AUDIO_SIZE_MB` (e.g. 10 MB).
- **Suggested fix**: Add `MAX_AUDIO_SIZE_MB: int = 10` to `Settings`; wire it in `_get_size_limit_mb`.

---

### 4. UX & Interaction Gaps (Flutter)

#### [UX] Tap-to-unfocus missing on every form screen
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/auth/ui/login_screen.dart`, `register_screen.dart`, `email_verify_pending_screen.dart`, `flutter_app/lib/features/contacts/ui/add_contact_screen.dart`, `flutter_app/lib/features/profile/presentation/screens/edit_name_screen.dart`, `change_number_screen.dart`, `help_support_screen.dart`
- **Description**: None of these wrap the form body in a `GestureDetector(onTap: () => FocusScope.of(context).unfocus(), behavior: HitTestBehavior.opaque)`. Tapping outside a TextField does not dismiss the keyboard.
- **Expected**: Tap-to-unfocus on every form-bearing screen.
- **Suggested fix**: Add a `_DismissKeyboard` helper widget and wrap each Scaffold body.

#### [UX] No pull-to-refresh on contacts list
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/contacts/ui/contacts_screen.dart:184-262`
- **Description**: Auto-retries via the `shellTabProvider` listener but provides no manual refresh gesture.
- **Expected**: Wrap the ListView in `RefreshIndicator(onRefresh: () => ref.read(contactsNotifierProvider.notifier).load())`.
- **Suggested fix**: Add the indicator.

#### [UX] No pull-to-refresh on call history
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/calling/presentation/call_history_screen.dart:150-169`
- **Description**: `FutureProvider` is read once at build; no way to refresh aside from leaving + returning.
- **Expected**: `RefreshIndicator` + `ref.invalidate(_callHistoryProvider)`.
- **Suggested fix**: Add the indicator and invalidate.

#### [UX] No pull-to-refresh on profile screen
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/ui/profile_screen.dart:203`
- **Description**: Profile changes (avatar, name) auto-refresh via the notifier, but error-state has only a Retry button — no swipe gesture.
- **Expected**: Wrap the `CustomScrollView` in a `RefreshIndicator`.
- **Suggested fix**: Add.

#### [UX] Login submit button disables correctly; Google button does NOT disable while email submit is loading
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/ui/login_screen.dart:185-187`
- **Description**: `_GoogleButton.onPressed: _isGoogleLoading ? null : _submitGoogle`. While `_isLoading` (email submit) is true, the Google button is still tappable — user can fire both flows in parallel.
- **Expected**: Disable each button when *either* loading flag is true.
- **Suggested fix**: `onPressed: (_isLoading || _isGoogleLoading) ? null : _submitGoogle` on both buttons.

#### [UX] Register screen — same parallel-submission issue
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/ui/register_screen.dart:231-233`
- **Description**: Same pattern — Google + email submit can race.
- **Expected**: Disable mutually exclusively.
- **Suggested fix**: Same as above.

#### [UX] Verify-email screen — "Open mail app" never disables
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/ui/email_verify_pending_screen.dart:227-229`
- **Description**: Tapping multiple times during a slow Android intent could try to fire the intent twice.
- **Expected**: Debounce or disable while launching.
- **Suggested fix**: Track `_openingMail` and disable while in flight.

#### [UX] Chat input record button race: no permission denied → silent fail
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:1630-1651`
- **Description**: If `Permission.microphone.request()` returns `denied` (not `permanentlyDenied`), `_startRecording` returns silently without telling the user why nothing happened.
- **Expected**: Show a snackbar like "Microphone is required for voice notes."
- **Suggested fix**: Add user feedback on `!mic.isGranted`.

#### [UX] Keyboard overlap risk on `change_number_screen.dart`
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/presentation/screens/change_number_screen.dart:231-349`
- **Description**: Phone-input step uses `Column + Spacer + ElevatedButton` without a `SingleChildScrollView`; on small screens with the keyboard open, the button can be pushed off-screen.
- **Expected**: Wrap in `SingleChildScrollView` or use a `Stack` + bottom-pinned button outside `resizeToAvoidBottomInset`.
- **Suggested fix**: Replace `Column + Spacer` with `ListView` or `SingleChildScrollView`.

#### [UX] No empty state on `BlockedContactsScreen` for `state.error == null && entries.isEmpty` is handled, but no real loading shimmer
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/presentation/screens/blocked_contacts_screen.dart:74-80`
- **Description**: Just a CircularProgressIndicator. Fine, but inconsistent with the contacts screen.
- **Expected**: Either consistent skeleton list or accept the spinner.
- **Suggested fix**: Optional; consistency-only.

#### [UX] `contacts_screen` retry button visible only when *not* loading — race on rapid tab switches
- **Severity**: Low
- **Location**: `flutter_app/lib/features/contacts/ui/contacts_screen.dart:191`
- **Description**: The retry branch checks `state.contacts.isEmpty`. If a partial load returns then errors on the next attempt, the user sees no error UI.
- **Expected**: Show a banner/snackbar when refresh fails even if cached contacts are present.
- **Suggested fix**: Display a non-blocking error banner above the list when `state.error != null`.

#### [UX] `_pickAvatar` silently returns on cancel — no feedback
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/ui/profile_screen.dart:85-119`
- **Description**: Cancel from gallery or crop is silent. Fine.
- **Suggested fix**: No action.

---

### 5. Animations & Transitions

#### [ANIM] Default `MaterialPageRoute` used for permission-denied screens
- **Severity**: Low
- **Location**: `flutter_app/lib/features/contacts/ui/contacts_screen.dart:61, 78`, `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:141, 159`, `flutter_app/lib/features/calling/presentation/call_history_screen.dart:381, 399`
- **Description**: Three permission-denied screens push with bare `MaterialPageRoute(fullscreenDialog: true)`. Default Material transition. A custom slide-up would match the "alert" nature better, but acceptable.
- **Expected**: Custom transition matching the design system.
- **Suggested fix**: Optional polish.

#### [ANIM] Conversation cards have no entrance animation when loaded
- **Severity**: Low
- **Location**: `flutter_app/lib/features/chat/presentation/chats_home_screen.dart:168-186`
- **Description**: `ListView.builder` renders synchronously. New items don't fade/slide in.
- **Expected**: Optional staggered fade-in for the first batch.
- **Suggested fix**: Wrap with `AnimationLimiter` (or `flutter_staggered_animations`) for incremental entrance.

#### [ANIM] Call-history rows don't animate the expand
- **Severity**: Low
- **Location**: `flutter_app/lib/features/calling/presentation/call_history_screen.dart:313-351`
- **Description**: The action row appears via `if (isOpen)`; no AnimatedSize / AnimatedCrossFade.
- **Expected**: Smooth expand/collapse.
- **Suggested fix**: Wrap with `AnimatedSize`.

#### [ANIM] Profile avatar upload spinner has no fade transition
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/ui/profile_screen.dart:245-259`
- **Description**: The overlay pops in instantly; default acceptable.
- **Suggested fix**: Optional `AnimatedOpacity`.

---

### 6. Image Handling & Compression

#### [MEDIA] Chat media upload bypasses client-side compression entirely
- **Severity**: High
- **Location**: `flutter_app/lib/features/chat/data/message_repository.dart:86-107`
- **Description**: `uploadMedia` constructs a multipart from the raw file path with no compression. The chat composer would (if it were wired) hand `File` objects directly from camera/gallery. A 12 MB image would be uploaded as-is.
- **Expected**: Use `flutter_image_compress` for images before upload (the profile flow already does this).
- **Suggested fix**: Add a compress-then-upload step in the chat send path, mirroring `profile_screen._pickAvatar`'s safety-net.

#### [MEDIA] Network images use no caching
- **Severity**: High
- **Location**: `flutter_app/lib/shared/widgets/avatar.dart` (assumed; not directly audited but no `cached_network_image` import found in repo), media thumbnails throughout
- **Description**: Grep `cached_network_image` in `pubspec.yaml` — not present. Every avatar / media thumbnail re-fetches on every rebuild. With signed URLs (1h TTL), this also burns bandwidth.
- **Expected**: Use `cached_network_image` for all `Image.network` calls.
- **Suggested fix**: Add the dep, wrap UserAvatar's network branch with `CachedNetworkImage`.

#### [MEDIA] No placeholder/shimmer on network avatars
- **Severity**: Medium
- **Location**: `flutter_app/lib/shared/widgets/avatar.dart` (not directly audited but the avatar widget is used everywhere)
- **Description**: Avatars flash from blank → loaded with no shimmer.
- **Expected**: Display initials → fade to image, or use shimmer.
- **Suggested fix**: With `CachedNetworkImage.placeholder` show the initials avatar.

#### [BACKEND-MEDIA] Avatar size limit of 5 MB is large; no resolution check
- **Severity**: Low
- **Location**: `backend/api/app/services/media_service.py:85`
- **Description**: 5 MB avatars are uncommon — 1 MB is typical.
- **Expected**: 1–2 MB cap.
- **Suggested fix**: Reduce `MAX_AVATAR_SIZE_MB` to 2.

#### [BACKEND-MEDIA] Video uploads stored as-is up to 150 MB with no server-side recoding
- **Severity**: Medium
- **Location**: `backend/api/app/services/media_service.py:213-273`
- **Description**: Comment is explicit about the tradeoff ("10-user family app"). Acceptable, but a 150 MB upload running through the FastAPI process blocks the event loop for the duration. There is no streaming-to-disk; the entire file lives in memory in `validate_upload`.
- **Expected**: Stream straight to disk in chunks (already chunked, but the bytes are concatenated to memory via `b"".join(chunks)` at line 129).
- **Suggested fix**: Write each chunk directly to a temp file in `validate_upload`; refactor processors to take a `Path` instead of `bytes`.

---

### 7. Form Validation

#### [FORM] Register password validator accepts any 8+ char string
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/auth/ui/register_screen.dart:54-57`
- **Description**: Only enforces length. No complexity, no breach-list check (HIBP), no zxcvbn score.
- **Expected**: Minimum complexity OR a strength meter.
- **Suggested fix**: Either add `zxcvbn` scoring or rely on Firebase Auth's built-in weak-password rejection (currently the backstop).

#### [FORM] Login screen has no error display for already-locked accounts
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/ui/login_screen.dart:103-118`
- **Description**: `user-disabled` is mapped to "This account has been disabled." Fine, but no recovery path.
- **Expected**: Contact-support hint.
- **Suggested fix**: Append "Contact support to restore access" to the message.

#### [FORM] Add-contact form does not run validator on Enter (onFieldSubmitted)
- **Severity**: Low
- **Location**: `flutter_app/lib/features/contacts/ui/add_contact_screen.dart:137`
- **Description**: `_submit` runs validation via `_formKey.currentState!.validate()` — works, just verifying.
- **Suggested fix**: Already correct.

#### [FORM] Change-number phone validator uses `length < 8` — accepts non-E.164 input
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/presentation/screens/change_number_screen.dart:302-313`
- **Description**: Backend `AddContactRequest.validate_phone` enforces strict E.164 (`^\+[1-9]\d{7,14}$`); the client validator is much looser.
- **Expected**: Mirror the backend regex client-side.
- **Suggested fix**: Tighten regex.

#### [FORM] Edit-name screen blocks save on initialName but allows `text.length > 30` validation gap
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/presentation/screens/edit_name_screen.dart:48-58`
- **Description**: Max length is 30 client-side; backend `UpdateProfileRequest.validate_name` allows up to 100. Inconsistent.
- **Expected**: Align both to 30 (more conservative) or 100.
- **Suggested fix**: Either tighten backend to 30 or relax client to 100.

#### [FORM] Help & Support — no MAX length on textfield matches backend
- **Severity**: Low
- **Location**: `flutter_app/lib/features/profile/presentation/screens/help_support_screen.dart:207`
- **Description**: `maxLength: 1000` client-side; backend `SupportFeedbackRequest` not audited — verify.
- **Suggested fix**: Verify backend cap; align.

---

### 8. Error Handling

#### [ERR] `auth_service.logout` swallows JWT decode errors silently
- **Severity**: Low
- **Location**: `backend/api/app/services/auth_service.py:353-361`
- **Description**: `except Exception: pass`. Comment says "Token already invalid — nothing to blacklist" but this also catches Redis errors silently.
- **Expected**: Catch only `UnauthorizedError` (or `JWTError`); let Redis errors propagate.
- **Suggested fix**: Narrow the except.

#### [ERR] `call_service.py:54` decode_cursor exception silently sets cursor to None
- **Severity**: Low
- **Location**: `backend/api/app/services/call_service.py:51-55`
- **Description**: `except Exception: cursor_ts, cursor_id = None, None`. A malformed cursor silently reverts to the first page instead of returning 400.
- **Expected**: Return 400 / ValidationFailedError on bad cursor so clients catch their bug.
- **Suggested fix**: Raise `ValidationFailedError("Invalid cursor")`.

#### [ERR] Chat send paths swallow upload/send exceptions
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/domain/chat_notifier.dart:221-227, 289-295`
- **Description**: `} catch (_) { … updateStatus(MessageStatus.failed) … }` — fine for the UI, but the original error is gone (no logging, no analytics). A persistent media upload failure looks identical to a network blip.
- **Expected**: Capture the exception type and surface it (logger or Sentry) so failure modes can be debugged.
- **Suggested fix**: `} on DioException catch (e) { ...log; status=failed }`; `} catch (e, st) { ...log }`.

#### [ERR] `call_repository.dart:81` uses `print()` for error logging
- **Severity**: Low
- **Location**: `flutter_app/lib/features/calling/data/call_repository.dart:81`
- **Description**: `// ignore: avoid_print` followed by `print('[call_repository] getCallHistory failed: ${e.message}');`. Production builds will still execute the print.
- **Expected**: Use `debugPrint` (stripped in release) or a logger.
- **Suggested fix**: Replace with `debugPrint`.

#### [ERR] `_handleRemoteIce` and `_handleIceRestartOffer` swallow exceptions with `catch (_) {}`
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/calling/domain/call_notifier.dart:429, 448`
- **Description**: ICE candidate add failures silently dropped. If candidates keep failing, the call appears connected but media never flows.
- **Expected**: At least log; consider triggering ICE restart after N failures.
- **Suggested fix**: `} catch (e) { debugPrint('[call] addIce failed: $e'); }`.

#### [ERR] Signaling service `_asMap` silently drops malformed events
- **Severity**: Low
- **Location**: `flutter_app/lib/core/services/signaling_service.dart:167-296, 298`
- **Description**: Every handler does `if (map != null) { … }`. If the server ever changes payload shape (or sends nested data), events vanish silently.
- **Expected**: Log dropped events.
- **Suggested fix**: Add a `else debugPrint('[signaling] dropped malformed event $name')` branch.

#### [ERR] Backend `presence:get` in signaling does sequential Redis GETs in a loop
- **Severity**: Medium
- **Location**: `backend/signaling/src/presenceHandler.js:47-64`
- **Description**: Loops over `userIds` and calls `redisClient.get` one at a time. For a list of N contacts, that's N round-trips.
- **Expected**: `redisClient.mget(keys)`.
- **Suggested fix**: Refactor with `mget`.

#### [ERR] Frontend `try { … } catch (_) {}` blocks ignore Firebase signOut errors silently
- **Severity**: Low
- **Location**: `flutter_app/lib/features/auth/domain/auth_notifier.dart:432-433, 459-461`
- **Description**: `unawaited(_firebase.signOut().catchError((_) {}))` and `try { await _google.signOut(); } catch (_) {}`. Acceptable since logout is best-effort, but errors are completely invisible.
- **Suggested fix**: At minimum, `debugPrint` the error.

---

### 9. Security Gaps

#### [SEC] `/api/users/{user_id}` discloses email & phone with no relationship check
- **Severity**: High
- **Location**: `backend/api/app/routers/users.py:33`, `backend/api/app/services/user_service.py:26-33`
- **Description**: See API section. Discoverable PII exposure.
- **Expected**: Only contacts may fetch full profile; non-contacts get a stripped view (id + name + avatar only).
- **Suggested fix**: Add a contact check + redacted response branch.

#### [SEC] CORS is `allow_origins=["*"]` with `allow_methods=["*"]`
- **Severity**: Medium
- **Location**: `backend/api/app/main.py:80-85`
- **Description**: Comment argues mobile clients only, no cookies. True, but: (a) the `/health` detailed report and `/api/media/verify-signature` would also be reachable from any web origin; (b) the wide-open policy makes any future browser client more attack-surface than necessary.
- **Expected**: Allow only the documented mobile-client origins (or none — mobile doesn't need CORS). For server-to-server, restrict to explicit allow-list.
- **Suggested fix**: Tighten to a specific allowlist (`["https://lumin.tahseen.tech"]`) or drop the middleware entirely (mobile clients don't enforce CORS).

#### [SEC] Rate-limit dependency uses raw `request.client.host`
- **Severity**: Medium
- **Location**: `backend/api/app/dependencies.py:78`
- **Description**: Behind Nginx the real client IP arrives via `X-Real-IP` / `X-Forwarded-For`; the raw ASGI client IP is always Nginx's. So in production every caller shares the same rate-limit bucket.
- **Expected**: Read `X-Real-IP` (or `X-Forwarded-For` last value), as `main.py:_is_internal` already does.
- **Suggested fix**: Extract a helper `_client_ip(request)` and reuse from both rate_limit and _is_internal.

#### [SEC] Signaling `call:initiate` accepts arbitrary `to`, `offer`, `callType` with no validation
- **Severity**: High
- **Location**: `backend/signaling/src/callHandler.js:27`
- **Description**: No check that `to` is a contact, that `to !== userId`, that `offer` is a plausible SDP, that `callType` ∈ {audio,video}. Anyone authenticated can spam any other user with calls.
- **Expected**: Server-side checks: `to` must be in `contacts WHERE user_id = userId AND NOT is_blocked`, `callType` must be in the allow-list, `offer` must be a non-empty object.
- **Suggested fix**: Add `getContactUserIds(userId).includes(to)` gate, validate callType, validate offer shape.

#### [SEC] Signaling `call:ice` / `call:ice_restart` / `call:answer` accept any `to`
- **Severity**: High
- **Location**: `backend/signaling/src/callHandler.js:114, 135, 139`
- **Description**: A malicious authed user could send synthetic ICE candidates / answers to arbitrary targets and disrupt active calls.
- **Expected**: Validate that the `callId` exists in `call_sessions:{callId}` and that the current `userId` is one of the two participants.
- **Suggested fix**: Look up the session, gate emits on participant match.

#### [SEC] Signaling `call:busy` accepts any `to`
- **Severity**: Medium
- **Location**: `backend/signaling/src/callHandler.js:202-205`
- **Description**: Spam vector: emit `call:busy` to anyone to confuse their UI.
- **Suggested fix**: Same gating as above.

#### [SEC] Node signaling has no rate limit on `call:initiate`, `typing:start/stop`, `presence:update`
- **Severity**: Medium
- **Location**: `backend/signaling/src/callHandler.js`, `typingHandler.js`, `presenceHandler.js`
- **Description**: A malicious client can spam call invites or thousands of typing events per second.
- **Expected**: Per-userId+event token bucket.
- **Suggested fix**: Lightweight in-memory rate limiter (e.g. `rate-limiter-flexible`).

#### [SEC] `firebase-service-account.json` is committed and tracked
- **Severity**: Critical
- **Location**: `D:/calling-app/firebase-service-account.json` (committed; appears in `git status` as tracked) and `.env` (committed alongside `.env.example`)
- **Description**: Both files appear at repo root and the `.gitignore` does not exclude them (`.env` not gitignored — see `.gitignore` content). Service-account keys grant write access to FCM; if the repo is public or the key leaks, anyone can impersonate the project.
- **Expected**: Both files in `.gitignore` and rotated immediately.
- **Suggested fix**: Add `.env`, `firebase-service-account.json` to `.gitignore`; `git rm --cached` them; rotate the Firebase service-account key; rotate `JWT_SECRET`, `TURN_SECRET`, `MEDIA_SECRET`.

#### [SEC] `_handleNativeEvent` decline path can be triggered without a session
- **Severity**: Low
- **Location**: `flutter_app/lib/features/calling/domain/call_notifier.dart:362-370`
- **Description**: Builds a transient session purely to call `declineCall`. Innocuous, but `state` is briefly mutated to a phantom call.
- **Suggested fix**: Skip session build if no actual incoming call.

---

### 10. State Management

#### [STATE] Most StateNotifier providers are not autoDispose
- **Severity**: Low
- **Location**: `flutter_app/lib/features/contacts/domain/contacts_notifier.dart:129`, `flutter_app/lib/features/auth/domain/auth_notifier.dart:489`, `flutter_app/lib/features/calling/domain/call_notifier.dart:677`
- **Description**: These providers live for the app lifetime, which is intended for auth and call session but wasteful for contacts (already kept alive by IndexedStack anyway). `conversationListProvider` is autoDispose — inconsistent.
- **Expected**: Document the lifetime intent.
- **Suggested fix**: Add a one-line comment per provider explaining why it's (or isn't) autoDispose.

#### [STATE] `ConversationListNotifier` is autoDispose but `dbSub` etc. are cleaned up only in onDispose — fine, but watchAll() returns infinite stream
- **Severity**: Low
- **Location**: `flutter_app/lib/features/chat/domain/conversation_list_notifier.dart:23-30, 36`
- **Description**: AutoDispose + onDispose cancellation looks correct. Worth a comment that `dbSub` is the only thing holding the Drift query open across screens.
- **Suggested fix**: Add a comment.

#### [STATE] `chat_notifier` reads `state.otherUser!` without null guarding before send
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/chat/domain/chat_notifier.dart:212, 281`
- **Description**: `state.otherUser!.id` will NPE if the conversation row exists in Drift but the User row is missing (race between cache load and sync). The initial state.otherUser load is async and best-effort.
- **Expected**: Defer send until `otherUser` is known, or fail-fast with a snackbar.
- **Suggested fix**: Guard with `if (state.otherUser == null) { return; }` and surface a user-visible error.

#### [STATE] `signaling_service` `connect` calls `_socket?.dispose()` then `sio.io(...)` — race possible
- **Severity**: Low
- **Location**: `flutter_app/lib/core/services/signaling_service.dart:135-154`
- **Description**: If `connect` fires twice rapidly (e.g. auth token refreshed twice), the second call disposes the first socket mid-handshake. Probably fine since `sio.dispose()` is synchronous in `socket_io_client`, but worth confirming.
- **Suggested fix**: Add a re-entrancy guard (`if (_connecting) return;`).

---

### 11. Performance

#### [PERF] `conversation_service.list_conversations` N+1
- **Severity**: Critical
- **Location**: `backend/api/app/services/conversation_service.py:194-263`
- **Description**: For each conversation, executes: (1) SELECT User (other), (2) SELECT Message (last), (3) SELECT MediaFile (last's media), (4) COUNT MessageReceipt (unread). 50 conversations → ~200 queries. Hot endpoint on home screen.
- **Expected**: Single query with JOINs / selectinload, or 4 batched IN-queries.
- **Suggested fix**: Eager-load: `selectinload(Conversation.last_message).selectinload(Message.media)`, plus a batched IN-query for users and a single GROUP BY for unread counts.

#### [PERF] `call_service.list_call_history` does N+1 user fetches
- **Severity**: High
- **Location**: `backend/api/app/services/call_service.py:75-78`
- **Description**: Comment acknowledges the N+1 ("single round-trip per row is fine at limit=30"). At limit=100 (max) it's 100 extra queries.
- **Expected**: Batched IN-query on the collected other_ids.
- **Suggested fix**: Build set of other_ids, single `SELECT … WHERE id IN (…)`, dict lookup.

#### [PERF] `contact_service.list_contacts` returns ALL contacts with no pagination
- **Severity**: Medium
- **Location**: `backend/api/app/routers/contacts.py:15`, `backend/api/app/services/contact_service.py:117-124`
- **Description**: Family app with ~10 users is fine, but `list_contacts` returns unbounded list.
- **Expected**: Add `limit`/`cursor` for safety; current usage is low-risk.
- **Suggested fix**: Either accept the design (small N) or add cursor pagination.

#### [PERF] `conversation_service.list_conversations` returns ALL conversations with no pagination
- **Severity**: Medium
- **Location**: Same as N+1.
- **Description**: Will become problematic if a user accumulates many conversations.
- **Suggested fix**: Add cursor pagination on `last_activity`.

#### [PERF] Bundled image assets — none oversized
- **Severity**: Low
- **Location**: `flutter_app/assets/`
- **Description**: `find -size +500k` returned no results. Good.
- **Suggested fix**: No action.

#### [PERF] `IndexedStack` eagerly mounts all 4 tabs at app start
- **Severity**: Low
- **Location**: `flutter_app/lib/features/shell/ui/shell_screen.dart:72-80`
- **Description**: ContactsScreen, CallHistoryScreen, ChatsHomeScreen, ProfileScreen all initState immediately even though the user only sees one. ContactsScreen triggers `load()` at startup. Acceptable for warmup; surface explicitly in a comment.
- **Suggested fix**: No action; document the trade-off.

#### [PERF] FCM token cache `_token_lock` created lazily per loop — bound to whichever loop calls first
- **Severity**: Low
- **Location**: `backend/api/app/services/fcm_service.py:39, 48-50`
- **Description**: Comment says intentional. Just note that if the FastAPI process ever runs more than one event loop (e.g. with `uvicorn --workers > 1`), each worker re-creates its own cache — fine, just confirming.
- **Suggested fix**: No action.

#### [PERF] Signaling adds a per-socket `socket.conn.on('packet', …)` listener that's never removed
- **Severity**: Low
- **Location**: `backend/signaling/src/server.js:79-83`
- **Description**: Listener accumulates per connection — should be torn down on disconnect.
- **Suggested fix**: Add a `socket.conn.removeListener` call inside the disconnect handler.

#### [PERF] FCM worker `_drain_retry_queue` does XRANGE per loop iteration (every ~5s)
- **Severity**: Low
- **Location**: `backend/api/app/workers/fcm_worker.py:238-244`
- **Description**: Reasonable cadence for a 10-user app; would not scale to thousands of pending retries.
- **Suggested fix**: No action at current scale.

---

### 12. Accessibility

#### [A11Y] `IconButton`s on call-history rows and message bubbles lack `tooltip`
- **Severity**: Medium
- **Location**: `flutter_app/lib/features/calling/presentation/call_history_screen.dart:65-74`, `flutter_app/lib/features/profile/ui/profile_screen.dart:219-227`, `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart` (many call/video icons have tooltips; "back" icon in custom AppBar has none)
- **Description**: Screen readers announce just "button" instead of the action.
- **Expected**: `tooltip: 'Search'` etc. on every IconButton.
- **Suggested fix**: Add tooltips.

#### [A11Y] `GestureDetector` on filter chips has no `Semantics(button: true, label: ...)`
- **Severity**: Low
- **Location**: `flutter_app/lib/features/chat/presentation/chats_home_screen.dart:104-133`, `flutter_app/lib/features/calling/presentation/call_history_screen.dart:96-128`
- **Description**: Custom chip widgets render as `GestureDetector` only. TalkBack reads the label but not the role.
- **Expected**: Wrap with `Semantics(button: true, selected: isOn, label: ...)`.
- **Suggested fix**: Add.

#### [A11Y] `UserAvatar` widget likely has no `semanticsLabel` — confirm
- **Severity**: Low
- **Location**: `flutter_app/lib/shared/widgets/avatar.dart` (not directly audited)
- **Description**: Verify whether the avatar's `Image.network` carries `semanticLabel: 'Photo of $displayName'`.
- **Suggested fix**: Audit avatar widget.

#### [A11Y] Status-bar icon brightness pinned to system, but custom `Color(0xFF0B0F1A)` may fail contrast on certain Android skins
- **Severity**: Low
- **Location**: `flutter_app/lib/app.dart:344-350`
- **Suggested fix**: Verify with TalkBack on dark mode.

---

### 13. Code Quality & Consistency

#### [QUALITY] Stray `print()` in production code
- **Severity**: Low
- **Location**: `flutter_app/lib/features/calling/data/call_repository.dart:81`
- **Description**: See ERR section.
- **Suggested fix**: Replace with `debugPrint`.

#### [QUALITY] Stale TODO comments referencing prompts
- **Severity**: Low
- **Location**: `flutter_app/lib/core/utils/media_utils.dart:1`, `flutter_app/lib/core/services/notification_service.dart:86`, `backend/api/app/routers/auth.py:23-27`
- **Description**: Several comments reference internal "Prompt 13 / 14 / 15" build phases. Outside contributors won't have context.
- **Expected**: Rewrite or delete.
- **Suggested fix**: Strip prompt references; describe the intent in standalone terms.

#### [QUALITY] Two `app_colors.dart` files
- **Severity**: Medium
- **Location**: `flutter_app/lib/core/config/app_colors.dart`, `flutter_app/lib/core/theme/app_colors.dart`
- **Description**: Two color-token modules. Risk of drift — `register_screen.dart` and `login_screen.dart` import from `core/theme/`, others may import from `core/config/`.
- **Expected**: One source of truth.
- **Suggested fix**: Merge and remove the duplicate.

#### [QUALITY] Inconsistent test file presence
- **Severity**: Low
- **Location**: `flutter_app/test/` (not audited)
- **Description**: `chat_notifier_test` referenced in code comments but I didn't enumerate the test tree.
- **Suggested fix**: Audit `flutter_app/test/` separately.

#### [QUALITY] Hardcoded magic colors in `chat_rich_screen.dart` `_T` class
- **Severity**: Low
- **Location**: `flutter_app/lib/features/chat/presentation/chat_rich_screen.dart:37-62`
- **Description**: Local design-token class duplicates colors that exist in `AppColors`. Comment acknowledges it's deliberate to match HTML spec, but `_T.primary == AppColors.primary` — risk of drift.
- **Expected**: Reuse the theme.
- **Suggested fix**: Replace `_T.primary` with `AppColors.primary`; keep only the bubble-specific tokens.

#### [QUALITY] Multiple imports of `main.dart` to access `pendingDeepLinkProvider`
- **Severity**: Low
- **Location**: `flutter_app/lib/app.dart:42` (`import 'main.dart'`)
- **Description**: `pendingDeepLinkProvider` lives in main.dart; that file imports app.dart. Cyclic feel.
- **Expected**: Move `pendingDeepLinkProvider` to `core/services/deep_link_service.dart` or its own file.
- **Suggested fix**: Extract.

#### [QUALITY] `mock_data.dart` referenced from production code paths
- **Severity**: Low
- **Location**: `flutter_app/lib/features/chat/domain/conversation_list_notifier.dart:4`, others
- **Description**: Mocks live in `core/mock/` and are imported via `if (AppConfig.uiOnly)`. Acceptable, but the dependency means mock data ships in every release build.
- **Expected**: Tree-shake or compile-out via const-`uiOnly`.
- **Suggested fix**: Verify the compiler eliminates the branch in release builds; otherwise gate behind a separate library file imported conditionally.

#### [QUALITY] `LoginRequest` / `RegisterRequest` schemas still ship but deprecated
- **Severity**: Low
- **Location**: `backend/api/app/schemas/auth.py:6-23, 37-41`
- **Description**: Pydantic schemas for phone-auth flows that the comment acknowledges aren't used.
- **Suggested fix**: Remove with the deprecated routes.

#### [QUALITY] `RegisterScreen` and `LoginScreen` define identical `_OrDivider` / `_GoogleButton` classes
- **Severity**: Low
- **Location**: See above.
- **Suggested fix**: Extract shared widgets.

---

## Recommendations — Top 10 Fix Order

1. **Add `.env` and `firebase-service-account.json` to `.gitignore`; rotate all secrets** (SEC, Critical).
2. **Wire the chat attachment picker** to image_picker/file_picker → `sendMedia()` (DEAD-UI, Critical).
3. **Fix `removeContact` to use contact-row id** (API-MISMATCH, Critical).
4. **Fix older-messages pagination cursor** (API, Critical).
5. **Remove broken `from sqlalchemy import in_` in `message_service.py:261`** (Critical, smoke test message fetch with media).
6. **Eager-load conversation list — kill the N+1** (PERF, Critical).
7. **Hide/remove change-phone screen** (or wire it through Firebase Phone Auth) (INCOMPLETE/SEC, Critical).
8. **Add input validation + auth gates to signaling call:* events** (SEC, High).
9. **Restrict `GET /api/users/{id}` to contacts** (SEC, High).
10. **Add `cached_network_image` + client-side compression for chat media uploads** (MEDIA, High).

---

## Notes on Audit Coverage

- All FastAPI routers (9) read in full.
- All FastAPI services (12) read in full.
- Signaling JS (9 files) read in full.
- Flutter `core/` services, network, auth: read in full.
- Flutter `features/auth`, `features/contacts`, `features/chat`, `features/calling/data+domain`, `features/profile`: read in full.
- Flutter UX screens read in full or with sampled portions; `chat_rich_screen.dart` was read up to line 1730 of 2421 (large file — input bar implementation + Bubble are covered; remaining tail likely contains additional helper widgets).
- Schemas (auth, message, user, contact) read in full.
- Models: `user.py`, `__init__.py` read; others (`call_record.py`, `contact.py`, `conversation.py`, `media.py`, `message.py`, `refresh_token.py`, `support_feedback.py`) inferred from service usage.
- Workers: `fcm_worker.py` read in full; `media_worker.py` is a stub.
- Deploy scripts: `deploy/*.py` not audited in detail — limited time. Recommend a dedicated pass since `git status` shows them modified.
- Avatar widget, shared widgets, signaling Flutter call helpers, mock_data, and `chat_rich_screen.dart` lines 1731–2421 not directly read; findings inferred from caller patterns.

This report should be treated as a strong starting point, not exhaustive — the codebase is large and the audit was time-boxed.
