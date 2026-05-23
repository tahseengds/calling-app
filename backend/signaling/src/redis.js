'use strict';
/**
 * Two ioredis connections:
 *   redisClient  — normal commands (GET/SET/DEL/XADD); shares DB 0 with FastAPI
 *                  so XADD to fcm_queue lands on the same stream the worker reads.
 *   subscriber   — dedicated subscribe-only connection (Redis Pub/Sub channels are
 *                  global, not per-DB, so this also connects to DB 0).
 */
const Redis = require('ioredis');
const config = require('../config');
const logger = require('./logger');

const redisClient = new Redis(config.redisUrl);
const subscriber = new Redis(config.redisUrl);

redisClient.on('error', (err) =>
  logger.error({ event: 'redis_error', error: err.message })
);
subscriber.on('error', (err) =>
  logger.error({ event: 'redis_subscriber_error', error: err.message })
);

module.exports = { redisClient, subscriber };
