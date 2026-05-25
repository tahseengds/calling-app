# Lumin

A private family communication app — messaging, voice calls, and video calls.

## Services

| Service | Technology | Port (internal) |
|---------|-----------|-----------------|
| FastAPI | Python 3.11, async | 8000 |
| Signaling | Node.js 20, Socket.IO | 8001 |
| Postgres | postgres:15 | 5432 |
| Redis | redis:7 | 6379 |
| Nginx | nginx:alpine | 80, 443 |

Postgres and Redis are **not** exposed to the host in production.

## Quick start

```bash
# 1. Copy and edit secrets
cp .env.example .env
# Edit .env — replace every CHANGE_ME_* value:
#   openssl rand -hex 64   → JWT_SECRET
#   openssl rand -hex 32   → TURN_SECRET, MEDIA_SECRET, POSTGRES_PASSWORD

# 2. Bring up the data layer first
docker compose up -d postgres redis

# 3. (After prompts 02-10 are applied) bring up everything
docker compose up -d

# Development (hot reload, exposed DB ports)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

## Domain

Replace `lumin.example.com` with your real domain everywhere marked `# TODO: replace domain`.
