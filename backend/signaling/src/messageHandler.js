'use strict';
/**
 * Redis Pub/Sub → Socket.IO bridge.
 *
 * FastAPI publishes events on three channel patterns:
 *   msg_delivery:{userId}  — new message or message_deleted
 *   receipt:{userId}       — delivered/read receipt
 *   presence:{userId}      — presence update (future use)
 *
 * This module subscribes with psubscribe and fans out to the matching user's
 * Socket.IO room.
 *
 * Client → server message:ack is accepted for completeness but the canonical
 * delivery acknowledgement path is the REST PUT /api/messages/delivered endpoint.
 * Flutter clients SHOULD call that REST endpoint; the socket event is optional.
 */
const { subscriber } = require('./redis');
const logger = require('./logger');

function registerMessageBridge(io) {
  subscriber.psubscribe('msg_delivery:*', 'receipt:*', 'presence:*', (err) => {
    if (err) {
      logger.error({ event: 'psubscribe_error', error: err.message });
    } else {
      logger.info({ event: 'pubsub_subscribed', patterns: ['msg_delivery:*', 'receipt:*', 'presence:*'] });
    }
  });

  subscriber.on('pmessage', (_pattern, channel, message) => {
    try {
      const payload = JSON.parse(message);

      if (channel.startsWith('msg_delivery:')) {
        const userId = channel.slice('msg_delivery:'.length);
        const event = payload.event === 'message_deleted' ? 'message:deleted' : 'message:new';
        io.to(userId).emit(event, payload);
        logger.debug({ event, userId });

      } else if (channel.startsWith('receipt:')) {
        const userId = channel.slice('receipt:'.length);
        io.to(userId).emit('message:ack', payload);
        logger.debug({ event: 'message:ack', userId });

      } else if (channel.startsWith('presence:')) {
        const userId = channel.slice('presence:'.length);
        io.to(userId).emit('presence:update', payload);
        logger.debug({ event: 'presence:update', userId });
      }
    } catch (err) {
      logger.error({ event: 'pmessage_parse_error', channel, error: err.message });
    }
  });
}

function registerMessageHandlers(socket) {
  // Optional lightweight ack; delivery tracking is handled via REST
  socket.on('message:ack', ({ messageId }) => {
    logger.debug({ event: 'message:ack_socket', userId: socket.userId, messageId });
  });
}

module.exports = { registerMessageBridge, registerMessageHandlers };
