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
  insertCallRecord,
};
