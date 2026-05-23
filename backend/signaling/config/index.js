'use strict';
require('dotenv').config();

const config = {
  port: parseInt(process.env.PORT || '8001', 10),

  // Redis DB 0 — shared with FastAPI for Pub/Sub channels and fcm_queue stream.
  // The signaling server's own state keys (socket_sessions:, call_sessions:, etc.)
  // also live here using their own prefixes; no collision risk.
  redisUrl: process.env.REDIS_URL || 'redis://redis:6379/0',

  jwt: {
    secret: process.env.JWT_SECRET,
    algorithm: process.env.JWT_ALGORITHM || 'HS256',
  },

  db: {
    connectionString: process.env.DATABASE_URL,
  },
};

if (!config.jwt.secret) {
  console.error('FATAL: JWT_SECRET is required');
  process.exit(1);
}

module.exports = config;
