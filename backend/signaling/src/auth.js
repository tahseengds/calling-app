'use strict';
const jwt = require('jsonwebtoken');
const config = require('../config');

/**
 * Verify a JWT and return { userId, jti }.
 * Accepts:
 *   - regular access tokens (no `type` claim, or type === 'access')
 *   - short-lived signal_token minted for offline call wakeups (type === 'signal')
 * Throws on invalid/expired token or disallowed type.
 *
 * `jti` is returned so the caller can check the FastAPI revocation set
 * (`token_revoked:{jti}` in Redis) — logout must cut off signaling too.
 */
function verifyToken(token) {
  const payload = jwt.verify(token, config.jwt.secret, {
    algorithms: [config.jwt.algorithm],
  });

  const type = payload.type;
  if (type !== undefined && type !== 'access' && type !== 'signal') {
    throw new Error(`Disallowed token type: ${type}`);
  }

  return { userId: String(payload.sub), jti: payload.jti };
}

/**
 * Mint a short-lived signal_token for an offline callee.
 * The woken app uses this to connect to signaling without a full login round-trip.
 */
function mintSignalToken(userId, callId) {
  return jwt.sign(
    { sub: userId, type: 'signal', call_id: callId },
    config.jwt.secret,
    { algorithm: config.jwt.algorithm, expiresIn: '60s' }
  );
}

module.exports = { verifyToken, mintSignalToken };
