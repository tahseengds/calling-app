'use strict';
/**
 * Per-(userId, event) token-bucket rate limiter. In-process; the signaling
 * server is single-process (no horizontal scaling planned for a 10-user
 * family app), so distributed buckets would be over-engineering.
 *
 * Caller stays trusted within the bucket window; once exceeded, isLimited()
 * returns true until the window rolls over. Buckets self-evict opportunistically
 * via cleanup() so the Map doesn't grow without bound.
 */
const logger = require('./logger');

const LIMITS = {
  'call:initiate':     { max: 5,   windowMs: 60_000 },
  'call:ice_restart':  { max: 5,   windowMs: 60_000 },
  'call:ice':          { max: 200, windowMs: 60_000 },
  'typing:start':      { max: 60,  windowMs: 60_000 },
  'typing:stop':       { max: 60,  windowMs: 60_000 },
  'presence:update':   { max: 30,  windowMs: 60_000 },
  'presence:get':      { max: 30,  windowMs: 60_000 },
};

// key = `${userId}:${event}` → { count, resetAt }
const _buckets = new Map();
let _lastCleanup = Date.now();
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

function _cleanupIfDue(now) {
  if (now - _lastCleanup < CLEANUP_INTERVAL_MS) return;
  _lastCleanup = now;
  for (const [k, v] of _buckets) {
    if (v.resetAt < now) _buckets.delete(k);
  }
}

/**
 * Returns true iff the event should be dropped because the user is over
 * the configured bucket. Returns false (allow) for events not in the table.
 */
function isLimited(userId, event) {
  const cfg = LIMITS[event];
  if (!cfg) return false;

  const now = Date.now();
  _cleanupIfDue(now);

  const key = `${userId}:${event}`;
  const bucket = _buckets.get(key);

  if (!bucket || bucket.resetAt < now) {
    _buckets.set(key, { count: 1, resetAt: now + cfg.windowMs });
    return false;
  }

  bucket.count++;
  if (bucket.count > cfg.max) {
    // Log once per bucket-cross so we can see abuse in docker logs.
    if (bucket.count === cfg.max + 1) {
      logger.warn({
        event: 'rate_limited',
        userId,
        socketEvent: event,
        max: cfg.max,
        windowMs: cfg.windowMs,
      });
    }
    return true;
  }
  return false;
}

module.exports = { isLimited };
