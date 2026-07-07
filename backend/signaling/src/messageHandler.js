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
  // FIX 8: also subscribe to user_events:* so block events delivered by the
  // FastAPI side fan out as socket events (currently used for user:blocked).
  subscriber.psubscribe(
    'msg_delivery:*',
    'receipt:*',
    'presence:*',
    'user_events:*',
    (err) => {
      if (err) {
        logger.error({ event: 'psubscribe_error', error: err.message });
      } else {
        logger.info({
          event: 'pubsub_subscribed',
          patterns: ['msg_delivery:*', 'receipt:*', 'presence:*', 'user_events:*'],
        });
      }
    },
  );

  subscriber.on('pmessage', (_pattern, channel, message) => {
    try {
      const payload = JSON.parse(message);

      if (channel.startsWith('msg_delivery:')) {
        const userId = channel.slice('msg_delivery:'.length);
        // Map FastAPI's payload.event → the Socket.IO event name. Default to
        // message:new for any unknown/legacy value so old clients keep working.
        const eventMap = {
          message_deleted: 'message:deleted',
          message_edited: 'message:edited',
          message_pinned: 'message:pinned',
          message_unpinned: 'message:unpinned',
          disappearing_set: 'conversation:disappearing',
          reaction_added: 'message:reaction_added',
          reaction_removed: 'message:reaction_removed',
        };
        const event = eventMap[payload.event] || 'message:new';
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

      } else if (channel.startsWith('user_events:')) {
        // FIX 8: forward per-user lifecycle events. payload.event names the
        // specific kind (currently only 'user_blocked'); we translate it to
        // a socket event of form 'user:<kind without user_ prefix>'.
        const userId = channel.slice('user_events:'.length);
        const eventKind = payload.event;
        const eventMap = {
          user_blocked: 'user:blocked',
        };
        const event = eventMap[eventKind];
        if (event) {
          io.to(userId).emit(event, payload);
          logger.debug({ event, userId });
        } else {
          logger.warn({ event: 'unknown_user_event', kind: eventKind, userId });
        }
      }
    } catch (err) {
      logger.error({ event: 'pmessage_parse_error', channel, error: err.message });
    }
  });
}

function registerMessageHandlers(socket) {
  // Optional lightweight ack; delivery tracking is handled via REST
  socket.on('message:ack', (payload) => {
    // Defensive destructure: an ack emitted with no argument would otherwise
    // throw synchronously in Socket.IO's dispatch and crash the process.
    const { messageId } = payload || {};
    logger.debug({ event: 'message:ack_socket', userId: socket.userId, messageId });
  });
}

module.exports = { registerMessageBridge, registerMessageHandlers };
