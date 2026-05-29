'use strict';
/**
 * Insert a "call log" chat message into the caller-callee conversation when
 * a call ends, and publish it on both users' msg_delivery Redis channels so
 * the existing socket bridge fans it out as a regular message:new event.
 *
 * Why here (Node) and not in FastAPI? Because the call lifecycle is
 * exclusively a Node concern — hangup/reject/missed/timeout all happen in
 * callHandler.js. Routing back to FastAPI just to insert a row would add
 * latency and a moving part. Node already has direct Postgres + Redis
 * access, and the message_delivery channel format is fully documented
 * (msg_delivery:{userId} → Socket.IO message:new).
 *
 * The wire shape we publish matches FastAPI's MessageResponse exactly so
 * Flutter doesn't need a separate parsing path. message_type='call_log'
 * is new but Flutter's enum-tolerant parser falls back gracefully on
 * unknown types (and we add it on the Flutter side at the same time).
 *
 * Outcomes vocabulary:
 *   answered  — callee picked up; duration_seconds > 0
 *   missed    — callee didn't answer in time (server timeout) OR caller
 *               cancelled before pickup
 *   declined  — callee explicitly tapped Decline
 *   busy      — callee was in another call
 *   failed    — call setup failed (network / ICE) on either side
 *
 * Direction is implied by sender_id: the caller is ALWAYS the sender of
 * the call_log message. Each client renders "outgoing" or "incoming" by
 * checking senderId === self.
 */
const { v4: uuidv4 } = require('uuid');
const { pool } = require('./db');
const { redisClient } = require('./redis');
const logger = require('./logger');

/**
 * @param {object} params
 * @param {string} params.callerId          UUID of the caller (becomes sender_id)
 * @param {string} params.calleeId          UUID of the callee
 * @param {string} params.callType          'audio' | 'video'
 * @param {string} params.outcome           see vocabulary above
 * @param {number} params.durationSeconds   integer; 0 for unanswered outcomes
 * @param {Date|string|null} [params.endedAt]  defaults to now()
 */
async function insertCallLogMessage({
  callerId,
  calleeId,
  callType,
  outcome,
  durationSeconds,
  endedAt = null,
}) {
  if (!callerId || !calleeId) {
    logger.warn({ event: 'call_log_missing_user_ids', callerId, calleeId });
    return;
  }

  const createdAt = endedAt ? new Date(endedAt) : new Date();
  const messageId = uuidv4();
  // The Flutter parser pulls these three keys back out of content.
  const content = JSON.stringify({
    call_type: callType,
    outcome,
    duration_seconds: Math.max(0, Math.round(durationSeconds || 0)),
  });

  // Sort participants the same way FastAPI's get_or_create_conversation
  // does (str ordering) so we hit the same row whether the call is
  // outgoing or incoming.
  const [a, b] = [callerId, calleeId].sort();

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Find or create the conversation between caller and callee.
    let convId;
    const existing = await client.query(
      `SELECT id FROM conversations
       WHERE participant_a = $1 AND participant_b = $2`,
      [a, b],
    );
    if (existing.rows.length > 0) {
      convId = existing.rows[0].id;
    } else {
      const created = await client.query(
        `INSERT INTO conversations (id, participant_a, participant_b)
         VALUES ($1, $2, $3)
         ON CONFLICT (participant_a, participant_b) DO NOTHING
         RETURNING id`,
        [uuidv4(), a, b],
      );
      if (created.rows.length > 0) {
        convId = created.rows[0].id;
      } else {
        // Race: someone else just created it. Re-query.
        const reread = await client.query(
          `SELECT id FROM conversations
           WHERE participant_a = $1 AND participant_b = $2`,
          [a, b],
        );
        convId = reread.rows[0].id;
      }
    }

    // 2. Insert the call_log message. Caller is always the sender.
    await client.query(
      `INSERT INTO messages
         (id, conversation_id, sender_id, message_type,
          content, status, created_at)
       VALUES ($1, $2, $3, 'call_log', $4, 'sent', $5)`,
      [messageId, convId, callerId, content, createdAt],
    );

    // 3. Bump the conversation summary so the chat list sorts correctly
    //    and shows the call log as the latest activity.
    await client.query(
      `UPDATE conversations
         SET last_message_id = $1, last_activity = $2
       WHERE id = $3`,
      [messageId, createdAt, convId],
    );

    // 4. Create a delivery receipt row for the callee (matches what FastAPI
    //    does for normal messages — without it, read-receipt logic would
    //    have no record to mark delivered/read later).
    await client.query(
      `INSERT INTO message_receipts (message_id, user_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [messageId, calleeId],
    );

    await client.query('COMMIT');

    // 5. Publish to both users' delivery channels. The signaling server's
    //    own message bridge will pick this up and emit message:new on the
    //    socket — the same path FastAPI uses for normal chat messages.
    const payload = {
      event: 'new_message',
      id: messageId,
      conversation_id: convId,
      sender_id: callerId,
      message_type: 'call_log',
      content,
      media_id: null,
      media: null,
      reply_to_id: null,
      status: 'sent',
      is_deleted: false,
      created_at: createdAt.toISOString(),
      updated_at: null,
      reactions: [],
    };
    const json = JSON.stringify(payload);
    await Promise.all([
      redisClient.publish(`msg_delivery:${callerId}`, json),
      redisClient.publish(`msg_delivery:${calleeId}`, json),
    ]);

    logger.info({
      event: 'call_log_inserted',
      messageId,
      convId,
      callerId,
      calleeId,
      outcome,
      durationSeconds,
    });
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { /* best effort */ }
    logger.error({
      event: 'call_log_insert_failed',
      callerId,
      calleeId,
      outcome,
      error: err.message,
    });
  } finally {
    client.release();
  }
}

module.exports = { insertCallLogMessage };
