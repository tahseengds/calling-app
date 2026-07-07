'use strict';
const { redisClient } = require('./redis');
const { getContactUserIds } = require('./db');
const { isLimited } = require('./rateLimit');
const logger = require('./logger');

const PRESENCE_TTL_S = 3600;
const ALLOWED_STATUSES = new Set(['online', 'offline', 'away', 'busy']);

/**
 * Broadcast a presence status to all of userId's contacts that currently have
 * a live socket session. Uses MGET to batch the session lookups so it's one
 * round-trip regardless of contact count.
 */
async function broadcastPresence(io, userId, status) {
  const lastSeen = new Date().toISOString();
  try {
    const contactIds = await getContactUserIds(userId);
    if (contactIds.length === 0) return;
    const keys = contactIds.map((id) => `socket_sessions:${id}`);
    const sessions = await redisClient.mget(keys);
    for (let i = 0; i < contactIds.length; i++) {
      if (sessions[i]) {
        io.to(contactIds[i]).emit('presence:update', {
          userId, status, lastSeen,
        });
      }
    }
  } catch (err) {
    logger.error({ event: 'broadcast_presence_error', userId, error: err.message });
  }
}

function registerPresenceHandlers(io, socket) {
  const { userId } = socket;

  // Client explicitly sets its status (e.g., 'busy', 'away')
  socket.on('presence:update', async (payload) => {
    if (isLimited(userId, 'presence:update')) return;
    const { status } = payload || {};
    if (typeof status !== 'string' || !ALLOWED_STATUSES.has(status)) return;
    try {
      const lastSeen = new Date().toISOString();
      await redisClient.set(
        `user_presence:${userId}`,
        JSON.stringify({ status, lastSeen }),
        'EX', PRESENCE_TTL_S
      );
      await broadcastPresence(io, userId, status);
      logger.info({ event: 'presence:update', userId, status });
    } catch (err) {
      logger.error({ event: 'presence_update_error', userId, error: err.message });
    }
  });

  // Client requests current presence for a list of users (e.g., on chat list open).
  // Batched into a single MGET so the latency is the same whether the user
  // requests 1 or 50 contacts.
  socket.on('presence:get', async (payload, callback) => {
    if (isLimited(userId, 'presence:get')) {
      if (typeof callback === 'function') callback({});
      return;
    }
    const userIds = Array.isArray(payload?.userIds) ? payload.userIds : [];
    // Cap to a sane upper bound — a malicious client can't ask us to scan
    // arbitrarily large key sets.
    const requested = userIds.slice(0, 100).filter((u) => typeof u === 'string');
    try {
      const result = {};
      if (requested.length === 0) {
        if (typeof callback === 'function') callback(result);
        else socket.emit('presence:data', result);
        return;
      }
      // Only reveal presence/last-seen for the caller's own contacts. Otherwise
      // a removed or blocked user can keep tracking a victim's online/offline
      // transitions and exact last-seen by polling arbitrary UUIDs.
      let contactIds;
      try {
        contactIds = new Set(await getContactUserIds(userId));
      } catch (err) {
        logger.error({ event: 'presence_get_contacts_error', userId, error: err.message });
        if (typeof callback === 'function') callback({});
        return;
      }
      const sliced = requested.filter((u) => u === userId || contactIds.has(u));
      if (sliced.length === 0) {
        if (typeof callback === 'function') callback(result);
        else socket.emit('presence:data', result);
        return;
      }
      const keys = sliced.map((u) => `user_presence:${u}`);
      const raws = await redisClient.mget(keys);
      sliced.forEach((u, i) => {
        const raw = raws[i];
        // Guard each parse: one corrupt value must not blank the whole
        // response (which would leave the client's ack un-fired).
        if (!raw) {
          result[u] = { status: 'offline', lastSeen: null };
          return;
        }
        try {
          result[u] = JSON.parse(raw);
        } catch (_) {
          result[u] = { status: 'offline', lastSeen: null };
        }
      });
      if (typeof callback === 'function') {
        callback(result);
      } else {
        socket.emit('presence:data', result);
      }
    } catch (err) {
      logger.error({ event: 'presence_get_error', userId, error: err.message });
      if (typeof callback === 'function') callback({});
    }
  });
}

module.exports = { registerPresenceHandlers, broadcastPresence };
