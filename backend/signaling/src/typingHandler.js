'use strict';
const { redisClient } = require('./redis');
const { isLimited } = require('./rateLimit');
const logger = require('./logger');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function registerTypingHandlers(io, socket) {
  const { userId } = socket;

  socket.on('typing:start', async (payload) => {
    if (isLimited(userId, 'typing:start')) return;
    const { to } = payload || {};
    if (typeof to !== 'string' || !UUID_RE.test(to)) return;
    try {
      // Key uses sorted pair so both directions share the same namespace
      const pair = [userId, to].sort().join(':');
      await redisClient.set(`typing:${pair}:${userId}`, '1', 'EX', 5);
      io.to(to).emit('typing:start', { from: userId });
      logger.debug({ event: 'typing:start', from: userId, to });
    } catch (err) {
      logger.error({ event: 'typing_start_error', userId, error: err.message });
    }
  });

  socket.on('typing:stop', async (payload) => {
    if (isLimited(userId, 'typing:stop')) return;
    const { to } = payload || {};
    if (typeof to !== 'string' || !UUID_RE.test(to)) return;
    try {
      const pair = [userId, to].sort().join(':');
      await redisClient.del(`typing:${pair}:${userId}`);
      io.to(to).emit('typing:stop', { from: userId });
      logger.debug({ event: 'typing:stop', from: userId, to });
    } catch (err) {
      logger.error({ event: 'typing_stop_error', userId, error: err.message });
    }
  });
}

module.exports = { registerTypingHandlers };
