'use strict';
const { redisClient } = require('./redis');
const { getContactUserIds } = require('./db');
const logger = require('./logger');

const PRESENCE_TTL_S = 3600;

/**
 * Broadcast a presence status to all of userId's contacts that currently have
 * a live socket session.
 */
async function broadcastPresence(io, userId, status) {
  const lastSeen = new Date().toISOString();
  try {
    const contactIds = await getContactUserIds(userId);
    for (const contactId of contactIds) {
      const sessionKey = await redisClient.get(`socket_sessions:${contactId}`);
      if (sessionKey) {
        io.to(contactId).emit('presence:update', { userId, status, lastSeen });
      }
    }
  } catch (err) {
    logger.error({ event: 'broadcast_presence_error', userId, error: err.message });
  }
}

function registerPresenceHandlers(io, socket) {
  const { userId } = socket;

  // Client explicitly sets its status (e.g., 'busy', 'away')
  socket.on('presence:update', async ({ status }) => {
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

  // Client requests current presence for a list of users (e.g., on chat list open)
  socket.on('presence:get', async ({ userIds }, callback) => {
    try {
      const result = {};
      for (const uid of (Array.isArray(userIds) ? userIds : [])) {
        const raw = await redisClient.get(`user_presence:${uid}`);
        result[uid] = raw
          ? JSON.parse(raw)
          : { status: 'offline', lastSeen: null };
      }
      if (typeof callback === 'function') {
        callback(result);
      } else {
        socket.emit('presence:data', result);
      }
    } catch (err) {
      logger.error({ event: 'presence_get_error', userId, error: err.message });
    }
  });
}

module.exports = { registerPresenceHandlers, broadcastPresence };
