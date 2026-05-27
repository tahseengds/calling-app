'use strict';
const { v4: uuidv4 } = require('uuid');
const { mintSignalToken } = require('./auth');
const { redisClient } = require('./redis');
const { getUserBrief, insertCallRecord, getContactUserIds } = require('./db');
const { isLimited } = require('./rateLimit');
const { insertCallLogMessage } = require('./callLogMessage');
const logger = require('./logger');

const RINGING_TTL_S = 120;    // Redis TTL while in ringing state
const ACTIVE_TTL_S = 4 * 3600; // Redis TTL once the call is answered
// Match the Flutter client's 45 s ring timeout (CallNotifier._ringTimeoutTimer).
// Previously this was 30 s, which created a 15 s window where the server had
// already flagged the call missed + sent a missed_call FCM + persisted the
// record, while the caller still saw "outgoing ringing" — and the callee's
// in-app incoming screen could still be visible. Aligning the two removes
// that confusion.
const RING_TIMEOUT_MS = 45_000;

const ALLOWED_CALL_TYPES = new Set(['audio', 'video']);
// UUID v4-ish — same regex the FastAPI side uses for path-param validation
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// In-process map of callId → setTimeout handle (cleared on answer/reject/hangup)
const ringTimers = new Map();

// ── Validation helpers ──────────────────────────────────────────────────────

function _isUuid(s) {
  return typeof s === 'string' && UUID_RE.test(s);
}

/** Offer/answer can be a non-empty SDP string or {sdp, type} object. */
function _isPlausibleSdp(o) {
  if (typeof o === 'string') return o.length > 0 && o.length < 20_000;
  if (o && typeof o === 'object' && !Array.isArray(o)) {
    return typeof o.sdp === 'string' && o.sdp.length > 0;
  }
  return false;
}

/** ICE candidate is either a string (legacy) or an object with `candidate`. */
function _isPlausibleIce(c) {
  if (c == null) return false;
  if (typeof c === 'string') return c.length > 0 && c.length < 4_000;
  if (typeof c === 'object' && !Array.isArray(c)) {
    return typeof c.candidate === 'string' || c.candidate === '';
  }
  return false;
}

async function _loadSession(callId) {
  if (!_isUuid(callId)) return null;
  const raw = await redisClient.get(`call_sessions:${callId}`);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function _peerOf(session, userId) {
  if (!session) return null;
  if (session.caller === userId) return session.callee;
  if (session.callee === userId) return session.caller;
  return null;
}

// ── FCM queue helper ────────────────────────────────────────────────────────

async function _addToFcmQueue(fields) {
  const args = [];
  for (const [k, v] of Object.entries(fields)) {
    args.push(k, String(v));
  }
  await redisClient.xadd('fcm_queue', 'MAXLEN', '~', 10000, '*', ...args);
}

// ── Handlers ────────────────────────────────────────────────────────────────

function registerCallHandlers(io, socket) {
  const { userId } = socket;

  // ── call:initiate ────────────────────────────────────────────────────────────
  socket.on('call:initiate', async (payload) => {
    if (isLimited(userId, 'call:initiate')) {
      socket.emit('call:error', { message: 'Too many calls — slow down.' });
      return;
    }

    // Defensive destructure — payload can be undefined/null from a hostile client.
    //
    // ── Wire format note ────────────────────────────────────────────────────
    // The Flutter client uses snake_case for all socket payloads (matches the
    // FastAPI REST conventions). We rename to camelCase locally because that's
    // idiomatic JS. Every destructure / emit in this file does the same
    // translation at the boundary.
    //
    // ── call_id source of truth ─────────────────────────────────────────────
    // Flutter generates a UUID in CallNotifier.startCall and stores it on
    // CallSession.callId. We MUST adopt that UUID rather than minting our own
    // — otherwise every subsequent inbound event (call:ice, call:ringing,
    // call:answer) carries a different ID than what the caller is filtering
    // by, and ICE candidates / answers get silently dropped.
    const {
      to,
      offer,
      call_type: callType,
      call_id: clientCallId,
    } = payload || {};

    // ── Input validation ─────────────────────────────────────────────────────
    if (!_isUuid(to)) {
      socket.emit('call:error', { message: 'Invalid target user.' });
      return;
    }
    if (to === userId) {
      socket.emit('call:error', { message: 'You can\'t call yourself.' });
      return;
    }
    if (!ALLOWED_CALL_TYPES.has(callType)) {
      socket.emit('call:error', { message: 'Invalid call type.' });
      return;
    }
    if (!_isPlausibleSdp(offer)) {
      socket.emit('call:error', { message: 'Invalid offer.' });
      return;
    }

    // ── Authorization: target must be a non-blocked contact ──────────────────
    let contactIds;
    try {
      contactIds = await getContactUserIds(userId);
    } catch (err) {
      logger.error({ event: 'call_initiate_contacts_lookup_failed', userId, error: err.message });
      socket.emit('call:error', { message: 'Internal error.' });
      return;
    }
    if (!contactIds.includes(to)) {
      logger.warn({ event: 'call_initiate_unauthorized', userId, to });
      socket.emit('call:error', { message: 'You can only call your contacts.' });
      return;
    }

    // Use the client-supplied UUID when valid (the common case — Flutter
    // always sends one). Fall back to a server-minted UUID for older clients
    // or hostile payloads. Reject collisions against an active session so a
    // malicious client can't hijack an existing call's stream.
    let callId;
    if (_isUuid(clientCallId)) {
      const existing = await redisClient.exists(`call_sessions:${clientCallId}`);
      if (existing) {
        logger.warn({
          event: 'call_initiate_id_collision',
          userId,
          callId: clientCallId,
        });
        socket.emit('call:error', { message: 'Call ID already in use.' });
        return;
      }
      callId = clientCallId;
    } else {
      callId = uuidv4();
    }
    try {
      const callerInfo = await getUserBrief(userId);
      const now = new Date().toISOString();

      await redisClient.set(
        `call_sessions:${callId}`,
        JSON.stringify({ caller: userId, callee: to, state: 'ringing', callType, startedAt: now }),
        'EX', RINGING_TTL_S
      );

      // ── Dual-delivery (Option A) ────────────────────────────────────────────
      // We ALWAYS emit on the socket AND queue an FCM data message, never one
      // or the other. Rationale:
      //   - Socket alone misses the case where the callee app is backgrounded
      //     but the socket connection is still alive (very common on Android,
      //     since the OS keeps backgrounded apps' connections open). Flutter
      //     can't show UI when backgrounded, so a socket-only delivery silently
      //     fails and the user just sees a missed-call notification 30 s later.
      //   - FCM alone has variable latency (typically <1 s, but can be 10–30 s
      //     under battery optimization / Doze), so foreground users wouldn't
      //     get instant ring.
      //   - The Flutter client dedups by call_id (CallNotifier._seenIncomingIds),
      //     so the receiver only sees one ring even when both arrive.
      //
      // Cost: one extra Redis XADD per call (~ms). The FCM worker queues real
      // pushes only for tokens that exist, so unregistered devices cost zero.

      // Flutter's handleIncomingCall reads:
      //   call_id, call_type, offer, from, from_user{id,name,avatar_url}
      // Keep that exact shape — flattening callerName/callerAvatar onto
      // the top-level payload would silently break the incoming UI.
      io.to(to).emit('call:incoming', {
        from: userId,
        call_id: callId,
        offer,
        call_type: callType,
        from_user: {
          id: userId,
          name: callerInfo?.name ?? 'Unknown',
          avatar_url: callerInfo?.avatar_url ?? null,
        },
      });

      const signalToken = mintSignalToken(to, callId);
      await _addToFcmQueue({
        type: 'incoming_call',
        recipient_id: to,
        call_id: callId,
        caller_id: userId,
        caller_name: callerInfo?.name ?? 'Unknown',
        caller_avatar: callerInfo?.avatar_url ?? '',
        call_type: callType,
        // sdp_offer is sent over FCM data — accept both string and {sdp,type} shapes
        sdp_offer: typeof offer === 'string' ? offer : (offer.sdp || ''),
        signal_token: signalToken,
      });
      const calleeSocketId = await redisClient.get(`socket_sessions:${to}`);
      logger.info({
        event: 'call:dispatched',
        callId,
        callee: to,
        socketAlive: Boolean(calleeSocketId),
      });

      socket.emit('call:ringing', { call_id: callId });

      // Ring timeout — emit missed after 30 s if no answer/reject/hangup
      const timer = setTimeout(async () => {
        try {
          ringTimers.delete(callId);
          const session = await _loadSession(callId);
          if (!session) return;
          if (session.state !== 'ringing') return;

          socket.emit('call:missed', { call_id: callId });
          io.to(to).emit('call:missed', { call_id: callId });

          const endedAt = new Date();
          await insertCallRecord({
            callId, callerId: userId, calleeId: to, callType,
            status: 'missed',
            startedAt: new Date(session.startedAt),
            endedAt, durationSeconds: 0,
          });

          // Inline call-log message — appears in both users' chat thread
          // immediately via the message:new socket bridge.
          await insertCallLogMessage({
            callerId: userId,
            calleeId: to,
            callType,
            outcome: 'missed',
            durationSeconds: 0,
            endedAt,
          });

          await _addToFcmQueue({
            type: 'missed_call',
            recipient_id: to,
            call_id: callId,
            caller_id: userId,
            caller_name: callerInfo?.name ?? 'Unknown',
            caller_avatar: callerInfo?.avatar_url ?? '',
            call_type: callType,
            sdp_offer: '',
            signal_token: '',
          });

          await redisClient.del(`call_sessions:${callId}`);
        } catch (err) {
          logger.error({ event: 'ring_timeout_error', callId, error: err.message });
        }
      }, RING_TIMEOUT_MS);

      ringTimers.set(callId, timer);
      logger.info({ event: 'call:initiate', callId, caller: userId, callee: to, callType });
    } catch (err) {
      logger.error({ event: 'call_initiate_error', callId, error: err.message });
      socket.emit('call:error', { message: 'Failed to initiate call' });
    }
  });

  // ── call:answer ──────────────────────────────────────────────────────────────
  socket.on('call:answer', async (payload) => {
    const { call_id: callId, answer } = payload || {};

    if (!_isPlausibleSdp(answer)) {
      logger.warn({ event: 'call_answer_invalid_sdp', callId, userId });
      return;
    }

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      logger.warn({ event: 'call_answer_unauthorized', callId, userId });
      return;
    }
    // Only the callee (not the caller) can answer their own outgoing call.
    if (session.callee !== userId) {
      logger.warn({ event: 'call_answer_wrong_role', callId, userId });
      return;
    }

    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      session.state = 'in-call';
      session.answeredAt = new Date().toISOString();
      await redisClient.set(`call_sessions:${callId}`, JSON.stringify(session), 'EX', ACTIVE_TTL_S);

      io.to(peer).emit('call:answered', { from: userId, call_id: callId, answer });
      logger.info({ event: 'call:answer', callId, callee: userId, caller: peer });
    } catch (err) {
      logger.error({ event: 'call_answer_error', callId, error: err.message });
    }
  });

  // ── call:ice ─────────────────────────────────────────────────────────────────
  socket.on('call:ice', async (payload) => {
    if (isLimited(userId, 'call:ice')) return;

    const { call_id: callId, candidate } = payload || {};
    if (!_isPlausibleIce(candidate)) return;

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      // Don't log every spurious ICE — they can be high-frequency.
      return;
    }
    io.to(peer).emit('call:ice', { from: userId, call_id: callId, candidate });
  });

  // ── call:ice_restart ─────────────────────────────────────────────────────────
  socket.on('call:ice_restart', async (payload) => {
    if (isLimited(userId, 'call:ice_restart')) return;

    const { call_id: callId, offer } = payload || {};
    if (!_isPlausibleSdp(offer)) return;

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      logger.warn({ event: 'call_ice_restart_unauthorized', callId, userId });
      return;
    }
    io.to(peer).emit('call:ice_restart', { from: userId, call_id: callId, offer });
  });

  // ── call:reject ──────────────────────────────────────────────────────────────
  socket.on('call:reject', async (payload) => {
    const { call_id: callId } = payload || {};

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      logger.warn({ event: 'call_reject_unauthorized', callId, userId });
      return;
    }
    // Only the callee can reject; caller would use call:hangup.
    if (session.callee !== userId) {
      logger.warn({ event: 'call_reject_wrong_role', callId, userId });
      return;
    }

    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      io.to(peer).emit('call:rejected', { from: userId, call_id: callId });

      const endedAt = new Date();
      await insertCallRecord({
        callId,
        callerId: session.caller,
        calleeId: session.callee,
        callType: session.callType,
        status: 'rejected',
        startedAt: new Date(session.startedAt),
        endedAt,
        durationSeconds: 0,
      });
      // Chat thread inline entry. Sender is always the caller — receiver
      // renders "Incoming · Declined", caller renders "Outgoing · Declined".
      await insertCallLogMessage({
        callerId: session.caller,
        calleeId: session.callee,
        callType: session.callType,
        outcome: 'declined',
        durationSeconds: 0,
        endedAt,
      });
      await redisClient.del(`call_sessions:${callId}`);
      logger.info({ event: 'call:reject', callId, userId });
    } catch (err) {
      logger.error({ event: 'call_reject_error', callId, error: err.message });
    }
  });

  // ── call:hangup ──────────────────────────────────────────────────────────────
  socket.on('call:hangup', async (payload) => {
    const { call_id: callId } = payload || {};

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      logger.warn({ event: 'call_hangup_unauthorized', callId, userId });
      return;
    }

    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      io.to(peer).emit('call:hangup', { from: userId, call_id: callId });

      // Write call record only once — ON CONFLICT DO NOTHING handles duplicates
      const endedAt = new Date();
      const startedAt = new Date(session.startedAt);
      const answeredAt = session.answeredAt ? new Date(session.answeredAt) : null;
      const status = session.state === 'in-call' ? 'completed' : 'missed';
      const durationSeconds = answeredAt
        ? Math.max(0, Math.round((endedAt - answeredAt) / 1000))
        : 0;

      await insertCallRecord({
        callId,
        callerId: session.caller,
        calleeId: session.callee,
        callType: session.callType,
        status,
        startedAt,
        answeredAt,
        endedAt,
        durationSeconds,
      });

      // Chat thread inline entry.
      //   • Hangup AFTER answer  → outcome 'answered', duration > 0
      //   • Hangup BEFORE answer → outcome 'missed' (caller cancelled before
      //     the callee picked up — from the callee's perspective it's a
      //     missed call, from the caller's it's a quick out-and-back).
      await insertCallLogMessage({
        callerId: session.caller,
        calleeId: session.callee,
        callType: session.callType,
        outcome: status === 'completed' ? 'answered' : 'missed',
        durationSeconds,
        endedAt,
      });

      await redisClient.del(`call_sessions:${callId}`);
      logger.info({ event: 'call:hangup', callId, userId });
    } catch (err) {
      logger.error({ event: 'call_hangup_error', callId, error: err.message });
    }
  });

  // ── call:busy ────────────────────────────────────────────────────────────────
  socket.on('call:busy', async (payload) => {
    const { call_id: callId } = payload || {};

    const session = await _loadSession(callId);
    const peer = _peerOf(session, userId);
    if (!peer) {
      logger.warn({ event: 'call_busy_unauthorized', callId, userId });
      return;
    }
    io.to(peer).emit('call:busy', { from: userId, call_id: callId });
    logger.info({ event: 'call:busy', from: userId, to: peer, callId });
  });
}

module.exports = { registerCallHandlers };
