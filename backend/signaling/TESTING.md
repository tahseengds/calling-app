# Signaling Server — Manual Test Checklist

## Prerequisites

- `docker compose up -d` (postgres, redis, fastapi, signaling all running)
- Two registered users with valid JWTs (register via `POST /api/auth/register` + verify OTP)
- Node.js 20+ available locally
- Install `socket.io-client`: `npm install socket.io-client`

## 1. Health check

Health endpoint is at `/health` (not `/signal/health`) because engine.io intercepts
all paths starting with `/signal`. Nginx (prompt 10) maps external `/signal/health`
→ internal `/health` via proxy_pass rewrite.

```bash
# Direct to container (inside Docker network):
curl http://localhost:8001/health
# → {"status":"ok"}

# Via Nginx (once prompt 10 is configured):
curl https://your-domain/signal/health
# → {"status":"ok"}
```

## 2. Two-client connection test

Create `test_client.js`:

```javascript
const { io } = require('socket.io-client');

const TOKEN_A = '<JWT for user A>';
const TOKEN_B = '<JWT for user B>';
const USER_B_ID = '<UUID of user B>';

const clientA = io('http://localhost:8001', {
  path: '/signal',
  transports: ['websocket'],
  auth: { token: TOKEN_A },
});

const clientB = io('http://localhost:8001', {
  path: '/signal',
  transports: ['websocket'],
  auth: { token: TOKEN_B },
});

clientA.on('connect', () => console.log('A connected:', clientA.id));
clientB.on('connect', () => {
  console.log('B connected:', clientB.id);

  // A initiates a call to B
  clientA.emit('call:initiate', {
    to: USER_B_ID,
    offer: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\n...',   // fake SDP
    callType: 'video',
  });
});

clientA.on('call:ringing', ({ callId }) => {
  console.log('A: call ringing, callId=', callId);
  global.callId = callId;
});

clientB.on('call:incoming', ({ callId, from, offer }) => {
  console.log('B: incoming call from', from, 'callId=', callId);
  // B answers
  clientB.emit('call:answer', { callId, to: from, answer: 'v=0\r\n...' });
});

clientA.on('call:answered', ({ callId, answer }) => {
  console.log('A: call answered, callId=', callId);
  // Exchange ICE candidates
  clientA.emit('call:ice', { callId, to: USER_B_ID, candidate: { candidate: 'candidate:0 1 UDP ...' } });
});

clientB.on('call:ice', ({ from, candidate }) => {
  console.log('B: got ICE from', from);
  clientB.emit('call:ice', { callId: global.callId, to: from, candidate });
});

// After 3 seconds, A hangs up
setTimeout(() => {
  console.log('A: hanging up');
  clientA.emit('call:hangup', { callId: global.callId, to: USER_B_ID });
}, 3000);

clientB.on('call:hangup', ({ callId }) => {
  console.log('B: call ended, callId=', callId);
  process.exit(0);
});
```

Run: `node test_client.js`

Expected output:
```
A connected: <id>
B connected: <id>
A: call ringing, callId=<uuid>
B: incoming call from <user_A_id> callId=<uuid>
A: call answered, callId=<uuid>
B: got ICE from <user_A_id>
A: hanging up
B: call ended, callId=<uuid>
```

## 3. Verify call_records row after hangup

```bash
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB \
  -c "SELECT id, status, duration_seconds FROM call_records ORDER BY created_at DESC LIMIT 1;"
```

Expected: one `completed` row with `duration_seconds ≈ 3`.

## 4. Invalid token rejected

```javascript
const bad = io('http://localhost:8001', {
  path: '/signal',
  transports: ['websocket'],
  auth: { token: 'invalid.token.here' },
});
bad.on('connect_error', (err) => console.log('Rejected:', err.message));
// → Rejected: Authentication failed
```

## 5. Offline callee → FCM queue entry

With user B **disconnected**, have A call B:

```bash
# Verify entry appears on fcm_queue
docker compose exec redis redis-cli XLEN fcm_queue
# → at least 1

docker compose exec redis redis-cli XRANGE fcm_queue - + COUNT 1
# → entry with type=incoming_call, sdp_offer=..., signal_token=...
```

## 6. Pub/Sub → socket bridge

With client B connected, publish a fake message event:

```bash
docker compose exec redis redis-cli PUBLISH "msg_delivery:<USER_B_ID>" \
  '{"event":"new_message","id":"test-123","sender_id":"<USER_A_ID>","content":"hello"}'
```

Client B's socket should receive `message:new` with that payload.

```javascript
clientB.on('message:new', (payload) => console.log('B got message:', payload));
```

## 7. Presence broadcast on disconnect

With both A and B connected, disconnect A:

```javascript
clientA.disconnect();
```

Client B should receive:
```javascript
clientB.on('presence:update', ({ userId, status }) => {
  console.log(userId, 'is now', status);
  // → <USER_A_ID> is now offline
});
```

## 8. Ring timeout (missed call)

Initiate a call from A to B while B is connected but doesn't answer.
After 30 seconds both clients receive `call:missed` and a `missed` row
appears in `call_records`.
