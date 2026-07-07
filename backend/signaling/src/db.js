'use strict';
const { Pool } = require('pg');
const config = require('../config');
const logger = require('./logger');

const pool = new Pool({ connectionString: config.db.connectionString });

pool.on('error', (err) =>
  logger.error({ event: 'pg_pool_error', error: err.message })
);

async function getUserBrief(userId) {
  const { rows } = await pool.query(
    'SELECT id, name, avatar_url FROM users WHERE id = $1',
    [userId]
  );
  return rows[0] || null;
}

async function getFcmToken(userId) {
  const { rows } = await pool.query(
    'SELECT fcm_token FROM users WHERE id = $1',
    [userId]
  );
  return rows[0]?.fcm_token || null;
}

/** Returns the user IDs of all non-blocked contacts for userId. */
async function getContactUserIds(userId) {
  const { rows } = await pool.query(
    'SELECT contact_user_id FROM contacts WHERE user_id = $1 AND is_blocked = false',
    [userId]
  );
  return rows.map((r) => String(r.contact_user_id));
}

/**
 * True if `targetId` has blocked `userId` (i.e. the target's contact row for
 * the caller is flagged is_blocked). The FastAPI backend enforces block in
 * both directions for messaging; the call path must do the same so a blocked
 * user can't ring the person who blocked them.
 */
async function isBlockedBy(userId, targetId) {
  const { rows } = await pool.query(
    'SELECT 1 FROM contacts WHERE user_id = $1 AND contact_user_id = $2 AND is_blocked = true LIMIT 1',
    [targetId, userId]
  );
  return rows.length > 0;
}

/**
 * True if `userId` may send interaction signals (typing, etc.) to `targetId`:
 * the target is a non-blocked contact AND the target has not blocked the user.
 * Single round-trip so it's cheap enough for the high-frequency typing path.
 */
async function canInteract(userId, targetId) {
  const { rows } = await pool.query(
    `SELECT
       EXISTS(SELECT 1 FROM contacts
              WHERE user_id = $1 AND contact_user_id = $2 AND is_blocked = false) AS forward,
       EXISTS(SELECT 1 FROM contacts
              WHERE user_id = $2 AND contact_user_id = $1 AND is_blocked = true) AS blocked`,
    [userId, targetId]
  );
  const r = rows[0];
  return Boolean(r && r.forward && !r.blocked);
}

/**
 * Persist a user's last-seen timestamp to Postgres. Redis holds the live value
 * (with a 24h TTL); writing it through on disconnect makes "last seen X" durable
 * past that TTL so the REST API can still return an accurate time days later.
 */
async function updateLastSeen(userId, lastSeen) {
  await pool.query(
    'UPDATE users SET last_seen = $2 WHERE id = $1',
    [userId, lastSeen]
  );
}

/**
 * Insert a call_records row. ON CONFLICT DO NOTHING so the first hangup wins
 * and a duplicate hangup event is harmless.
 */
async function insertCallRecord({
  callId,
  callerId,
  calleeId,
  callType,
  status,
  startedAt,
  answeredAt,
  endedAt,
  durationSeconds,
}) {
  await pool.query(
    `INSERT INTO call_records
       (id, caller_id, callee_id, call_type, status,
        started_at, answered_at, ended_at, duration_seconds)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     ON CONFLICT (id) DO NOTHING`,
    [callId, callerId, calleeId, callType, status,
     startedAt, answeredAt || null, endedAt, durationSeconds]
  );
}

module.exports = {
  pool,
  getUserBrief,
  getFcmToken,
  getContactUserIds,
  isBlockedBy,
  canInteract,
  updateLastSeen,
  insertCallRecord,
};
