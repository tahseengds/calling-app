'use strict';
const { redisClient } = require('./redis');
const logger = require('./logger');

function registerTypingHandlers(io, socket) {
  const { userId } = socket;

  socket.on('typing:start', async ({ to }) => {
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

  socket.on('typing:stop', async ({ to }) => {
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
