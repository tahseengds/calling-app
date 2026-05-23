'use strict';
const http = require('http');
const { Server } = require('socket.io');
const config = require('../config');
const { redisClient } = require('./redis');
const { verifyToken } = require('./auth');
const { registerCallHandlers } = require('./callHandler');
const { registerPresenceHandlers, broadcastPresence } = require('./presenceHandler');
const { registerTypingHandlers } = require('./typingHandler');
const { registerMessageBridge, registerMessageHandlers } = require('./messageHandler');
const logger = require('./logger');

// ── HTTP server ───────────────────────────────────────────────────────────────
// engine.io (socket.io's transport layer) calls server.removeAllListeners('request')
// when it attaches, then adds its OWN listener that intercepts every URL starting
// with the configured path ('/signal'). Requests to '/signal/health' are therefore
// intercepted by engine.io and returned as 400 (not a valid handshake).
//
// Fix: register the health endpoint at '/health' (no '/signal' prefix) so engine.io
// forwards it to the original listener chain. Nginx (prompt 10) routes the external
// path /signal/health → /health on this container.

const httpServer = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
  }
  // All other paths are handled by engine.io (added after createServer).
});

// ── Socket.IO ─────────────────────────────────────────────────────────────────

const io = new Server(httpServer, {
  cors: { origin: false },       // mobile clients only — no browser CORS needed
  transports: ['websocket'],
  pingTimeout: 60_000,
  pingInterval: 25_000,
  upgradeTimeout: 10_000,
  path: '/signal',
});

// Auth middleware — runs before every connection
io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) return next(new Error('No token'));
  try {
    const { userId } = verifyToken(token);
    socket.userId = userId;
    next();
  } catch (err) {
    logger.warn({ event: 'auth_rejected', error: err.message });
    next(new Error('Authentication failed'));
  }
});

// Pub/Sub → Socket.IO bridge (process-level, registered once)
registerMessageBridge(io);

// ── Connection handler ────────────────────────────────────────────────────────

io.on('connection', async (socket) => {
  const { userId } = socket;
  logger.info({ event: 'connected', userId, socketId: socket.id });

  try {
    // Register in Redis and join user's own room for targeted emits
    await redisClient.set(`socket_sessions:${userId}`, socket.id, 'EX', 3600);
    socket.join(userId);

    // Set presence online and notify contacts
    await redisClient.set(
      `user_presence:${userId}`,
      JSON.stringify({ status: 'online', lastSeen: new Date().toISOString() }),
      'EX', 3600
    );
    await broadcastPresence(io, userId, 'online');

    // Refresh session TTL on each received ping so long-lived connections stay registered
    socket.conn.on('packet', async (packet) => {
      if (packet.type === 'ping') {
        await redisClient.expire(`socket_sessions:${userId}`, 3600);
      }
    });
  } catch (err) {
    logger.error({ event: 'connection_setup_error', userId, error: err.message });
  }

  // Register domain handlers
  registerCallHandlers(io, socket);
  registerPresenceHandlers(io, socket);
  registerTypingHandlers(io, socket);
  registerMessageHandlers(socket);

  // ── Disconnect ──────────────────────────────────────────────────────────────
  socket.on('disconnect', async (reason) => {
    logger.info({ event: 'disconnected', userId, reason });
    try {
      await redisClient.del(`socket_sessions:${userId}`);
      // Keep last-seen in presence for 24 h so chat lists can show "last seen X"
      await redisClient.set(
        `user_presence:${userId}`,
        JSON.stringify({ status: 'offline', lastSeen: new Date().toISOString() }),
        'EX', 86400
      );
      await broadcastPresence(io, userId, 'offline');
    } catch (err) {
      logger.error({ event: 'disconnect_cleanup_error', userId, error: err.message });
    }
  });
});

// ── Start ─────────────────────────────────────────────────────────────────────

httpServer.listen(config.port, () => {
  logger.info({ event: 'server_started', port: config.port });
});
