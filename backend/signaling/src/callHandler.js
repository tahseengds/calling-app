'use strict';
const { v4: uuidv4 } = require('uuid');
const { mintSignalToken } = require('./auth');
const { redisClient } = require('./redis');
const { getUserBrief, getFcmToken, insertCallRecord } = require('./db');
const logger = require('./logger');

const RINGING_TTL_S = 120;    // Redis TTL while in ringing state
const ACTIVE_TTL_S = 4 * 3600; // Redis TTL once the call is answered
const RING_TIMEOUT_MS = 30_000; // emit call:missed after 30 s with no answer

// In-process map of callId → setTimeout handle (cleared on answer/reject/hangup)
const ringTimers = new Map();

async function _addToFcmQueue(fields) {
  const args = [];
  for (const [k, v] of Object.entries(fields)) {
    args.push(k, String(v));
  }
  await redisClient.xadd('fcm_queue', 'MAXLEN', '~', 10000, '*', ...args);
}

function registerCallHandlers(io, socket) {
  const { userId } = socket;

  // ── call:initiate ────────────────────────────────────────────────────────────
  socket.on('call:initiate', async ({ to, offer, callType }) => {
    const callId = uuidv4();
    try {
      const callerInfo = await getUserBrief(userId);
      const now = new Date().toISOString();

      await redisClient.set(
        `call_sessions:${callId}`,
        JSON.stringify({ caller: userId, callee: to, state: 'ringing', callType, startedAt: now }),
        'EX', RINGING_TTL_S
      );

      const calleeSocketId = await redisClient.get(`socket_sessions:${to}`);
      if (calleeSocketId) {
        io.to(to).emit('call:incoming', {
          from: userId,
          callId,
          offer,
          callType,
          callerName: callerInfo?.name ?? 'Unknown',
          callerAvatar: callerInfo?.avatar_url ?? null,
        });
      } else {
        const signalToken = mintSignalToken(to, callId);
        await _addToFcmQueue({
          type: 'incoming_call',
          recipient_id: to,
          call_id: callId,
          caller_id: userId,
          caller_name: callerInfo?.name ?? 'Unknown',
          caller_avatar: callerInfo?.avatar_url ?? '',
          call_type: callType,
          sdp_offer: offer,
          signal_token: signalToken,
        });
        logger.info({ event: 'call:fcm_queued', callId, callee: to });
      }

      socket.emit('call:ringing', { callId });

      // Ring timeout — emit missed after 30 s if no answer/reject/hangup
      const timer = setTimeout(async () => {
        try {
          ringTimers.delete(callId);
          const raw = await redisClient.get(`call_sessions:${callId}`);
          if (!raw) return;
          const session = JSON.parse(raw);
          if (session.state !== 'ringing') return;

          socket.emit('call:missed', { callId });
          io.to(to).emit('call:missed', { callId });

          const endedAt = new Date();
          await insertCallRecord({
            callId, callerId: userId, calleeId: to, callType,
            status: 'missed',
            startedAt: new Date(session.startedAt),
            endedAt, durationSeconds: 0,
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
  socket.on('call:answer', async ({ callId, to, answer }) => {
    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      const raw = await redisClient.get(`call_sessions:${callId}`);
      if (raw) {
        const session = JSON.parse(raw);
        session.state = 'in-call';
        session.answeredAt = new Date().toISOString();
        await redisClient.set(`call_sessions:${callId}`, JSON.stringify(session), 'EX', ACTIVE_TTL_S);
      }

      io.to(to).emit('call:answered', { from: userId, callId, answer });
      logger.info({ event: 'call:answer', callId, callee: userId, caller: to });
    } catch (err) {
      logger.error({ event: 'call_answer_error', callId, error: err.message });
    }
  });

  // ── call:ice / call:ice_restart ──────────────────────────────────────────────
  socket.on('call:ice', ({ callId, to, candidate }) => {
    io.to(to).emit('call:ice', { from: userId, callId, candidate });
  });

  socket.on('call:ice_restart', ({ callId, to, offer }) => {
    io.to(to).emit('call:ice_restart', { from: userId, callId, offer });
  });

  // ── call:reject ──────────────────────────────────────────────────────────────
  socket.on('call:reject', async ({ callId, to }) => {
    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      io.to(to).emit('call:rejected', { from: userId, callId });

      const raw = await redisClient.get(`call_sessions:${callId}`);
      if (raw) {
        const session = JSON.parse(raw);
        await insertCallRecord({
          callId, callerId: session.caller, calleeId: session.callee,
          callType: session.callType, status: 'rejected',
          startedAt: new Date(session.startedAt),
          endedAt: new Date(), durationSeconds: 0,
        });
        await redisClient.del(`call_sessions:${callId}`);
      }
      logger.info({ event: 'call:reject', callId, userId });
    } catch (err) {
      logger.error({ event: 'call_reject_error', callId, error: err.message });
    }
  });

  // ── call:hangup ──────────────────────────────────────────────────────────────
  socket.on('call:hangup', async ({ callId, to }) => {
    try {
      const timer = ringTimers.get(callId);
      if (timer) { clearTimeout(timer); ringTimers.delete(callId); }

      io.to(to).emit('call:hangup', { from: userId, callId });

      // Write call record only once — ON CONFLICT DO NOTHING handles duplicates
      const raw = await redisClient.get(`call_sessions:${callId}`);
      if (raw) {
        const session = JSON.parse(raw);
        const endedAt = new Date();
        const startedAt = new Date(session.startedAt);
        const answeredAt = session.answeredAt ? new Date(session.answeredAt) : null;
        const status = session.state === 'in-call' ? 'completed' : 'missed';
        const durationSeconds = answeredAt
          ? Math.max(0, Math.round((endedAt - answeredAt) / 1000))
          : 0;

        await insertCallRecord({
          callId, callerId: session.caller, calleeId: session.callee,
          callType: session.callType, status,
          startedAt, answeredAt, endedAt, durationSeconds,
        });
        await redisClient.del(`call_sessions:${callId}`);
      }
      logger.info({ event: 'call:hangup', callId, userId });
    } catch (err) {
      logger.error({ event: 'call_hangup_error', callId, error: err.message });
    }
  });

  // ── call:busy ────────────────────────────────────────────────────────────────
  socket.on('call:busy', ({ to }) => {
    io.to(to).emit('call:busy', { from: userId });
    logger.info({ event: 'call:busy', from: userId, to });
  });
}

module.exports = { registerCallHandlers };
