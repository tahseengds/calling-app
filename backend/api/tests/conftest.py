"""
Test fixtures.

Root-cause of event-loop issues: the module-level asyncpg pool in app/db.py
is bound to the first event loop that uses it. pytest-asyncio 0.23 gives each
async test its own event loop, so the pool becomes invalid after the first test.

Fix: override the get_db dependency per test with a NullPool engine that
creates a fresh connection for every request — no pool, no loop binding.
Redis is also freshly connected per test for the same reason.
All fixtures are function-scoped.

Tests run inside Docker where postgres and redis are on the app_network.
"""
import asyncio
import itertools

import pytest
import redis.asyncio as aioredis
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import NullPool

from app.config import settings
from app.db import get_db as _original_get_db

# ── wipe all tables once per test session ────────────────────────────────────
# Uses asyncio.run() inside a sync fixture to avoid pytest-asyncio event-loop
# scope conflicts. NullPool creates a fresh connection that is closed immediately.
@pytest.fixture(scope="session", autouse=True)
def clean_db() -> None:
    """Truncate all application tables before the test session begins."""
    async def _truncate() -> None:
        engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
        async with engine.begin() as conn:
            await conn.execute(text(
                "TRUNCATE users CASCADE"  # cascades to contacts, refresh_tokens, etc.
            ))
        await engine.dispose()

    asyncio.run(_truncate())


# ── unique email generator ────────────────────────────────────────────────────
_counter = itertools.count(1)


@pytest.fixture
def email() -> str:
    """Return a unique email address per test invocation."""
    n = next(_counter)
    return f"test{n}@example.com"


# ── function-scoped Redis client ───────────────────────────────────────────────
@pytest.fixture
async def redis_client() -> aioredis.Redis:
    """Fresh Redis connection on this test's event loop."""
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    yield r
    await r.aclose()


# ── HTTP client with NullPool DB override ────────────────────────────────────
@pytest.fixture
async def client(redis_client: aioredis.Redis) -> AsyncClient:
    """
    FastAPI test client:
      - redis_client is attached to app.state (lifespan doesn't run via ASGITransport).
      - get_db is overridden with a NullPool engine so every request gets a
        fresh asyncpg connection on the current test's event loop.
    """
    from app.main import create_app

    app = create_app()
    app.state.redis = redis_client

    # NullPool: no connection caching → safe across different event loops
    test_engine = create_async_engine(settings.DATABASE_URL, poolclass=NullPool)
    _session_factory = async_sessionmaker(test_engine, expire_on_commit=False)

    async def _override_get_db() -> AsyncSession:  # type: ignore[override]
        async with _session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[_original_get_db] = _override_get_db

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as c:
        yield c

    app.dependency_overrides.clear()
    await test_engine.dispose()


# ── clear rate-limit keys before every test ───────────────────────────────────
@pytest.fixture(autouse=True)
async def clear_rate_limits(redis_client: aioredis.Redis) -> None:
    keys = await redis_client.keys("ratelimit:*")
    if keys:
        await redis_client.delete(*keys)
