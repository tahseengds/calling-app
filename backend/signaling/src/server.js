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
const { updateLastSeen } = require('./db');
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
    return;
  }
  // engine.io intercepts '/signal*' before this listener runs; anything else
  // that reaches here is not a route we serve. Close it out with a 404 instead
  // of leaving the socket open until Node's requestTimeout (~5 min).
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
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
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) return next(new Error('No token'));
  try {
    const { userId, jti } = verifyToken(token);
    // Parity with the FastAPI backend: a token whose jti has been revoked
    // (logout) must not be able to open a socket. Fail closed only on an
    // actual revocation hit — a Redis lookup error should not lock everyone
    // out of signaling, so it falls through to allow (the token signature and
    // expiry were already verified above).
    if (jti) {
      try {
        if (await redisClient.exists(`token_revoked:${jti}`)) {
          return next(new Error('Token revoked'));
        }
      } catch (err) {
        logger.error({ event: 'revocation_check_failed', error: err.message });
      }
    }
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

  // Named ping handler so we can remove it on disconnect — engine.io can
  // re-use the underlying connection (e.g. transport upgrades), and an
  // unnamed listener would accumulate over the connection's lifetime.
  const onPing = async (packet) => {
    if (packet.type === 'ping') {
      // Best-effort TTL refresh. A Redis hiccup here must never bubble up as an
      // unhandled rejection (which crashes the whole process under Node ≥15).
      try {
        await redisClient.expire(`socket_sessions:${userId}`, 3600);
      } catch (err) {
        logger.error({ event: 'ping_ttl_refresh_failed', userId, error: err.message });
      }
    }
  };

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
    socket.conn.on('packet', onPing);
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
    // Detach the packet listener so it doesn't leak into a reused engine.io
    // connection. socket.conn may already be gone in some disconnect paths;
    // guard defensively.
    try {
      socket.conn?.off('packet', onPing);
    } catch (_) {
      // Ignore — listener removal is best-effort.
    }
    try {
      // Reconnect race guard: on a network flap the new socket registers
      // (`SET socket_sessions:{userId}`) before this stale socket's disconnect
      // fires. If the stored socket id is no longer ours, a newer connection
      // owns the session — do not delete it or mark the (online) user offline.
      const current = await redisClient.get(`socket_sessions:${userId}`);
      if (current && current !== socket.id) {
        logger.info({ event: 'disconnect_superseded', userId, socketId: socket.id });
        return;
      }

      const lastSeen = new Date().toISOString();
      await redisClient.del(`socket_sessions:${userId}`);
      // Keep last-seen in presence for 24 h so chat lists can show "last seen X"
      await redisClient.set(
        `user_presence:${userId}`,
        JSON.stringify({ status: 'offline', lastSeen }),
        'EX', 86400
      );
      // Persist to Postgres so "last seen X" survives past the 24h Redis TTL.
      // Best-effort: a DB hiccup must not break the disconnect path.
      updateLastSeen(userId, lastSeen).catch((err) =>
        logger.error({ event: 'last_seen_persist_error', userId, error: err.message })
      );
      await broadcastPresence(io, userId, 'offline');
    } catch (err) {
      logger.error({ event: 'disconnect_cleanup_error', userId, error: err.message });
    }
  });
});

// ── Process-level safety net ────────────────────────────────────────────────
// Socket.IO does not catch exceptions thrown inside event listeners, and a
// bare `await` on a transient Redis error rejects into the void. Under Node ≥15
// an unhandledRejection terminates the process by default — one malformed
// event or a 2-second Redis blip during a call would drop every user. Log and
// keep running instead; a genuinely fatal state will surface elsewhere.
process.on('unhandledRejection', (reason) => {
  logger.error({
    event: 'unhandled_rejection',
    error: reason instanceof Error ? reason.message : String(reason),
    stack: reason instanceof Error ? reason.stack : undefined,
  });
});
process.on('uncaughtException', (err) => {
  logger.error({ event: 'uncaught_exception', error: err.message, stack: err.stack });
});

// ── Start ─────────────────────────────────────────────────────────────────────

httpServer.listen(config.port, () => {
  logger.info({ event: 'server_started', port: config.port });
});
