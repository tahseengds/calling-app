"""
FamilyLink FastAPI application factory.
"""
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

import redis.asyncio as aioredis
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.config import settings
from app.db import engine
from app.routers import auth as auth_router
from app.routers import calls as calls_router
from app.routers import contacts as contacts_router
from app.routers import conversations as conversations_router
from app.routers import media as media_router
from app.routers import messages as messages_router
from app.routers import users as users_router
from app.utils.exceptions import AppError
from app.utils.storage import ensure_media_dirs

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    # ── Startup ──────────────────────────────────────────────────────────────
    redis_client = aioredis.from_url(
        settings.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
    )
    await redis_client.ping()
    app.state.redis = redis_client
    logger.info("Redis connected at %s", settings.REDIS_URL)

    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    logger.info("Database connection verified")

    ensure_media_dirs()
    logger.info("Media directories verified at %s", settings.MEDIA_BASE_PATH)

    yield

    # ── Shutdown ─────────────────────────────────────────────────────────────
    await redis_client.aclose()
    await engine.dispose()
    logger.info("Connections closed")


def create_app() -> FastAPI:
    app = FastAPI(
        title="FamilyLink API",
        version="1.0.0",
        lifespan=lifespan,
        # Disable interactive docs in production
        docs_url="/api/docs" if settings.DEBUG else None,
        redoc_url=None,
    )

    # ── CORS ──────────────────────────────────────────────────────────────────
    # The client is a mobile app — there is no browser origin restriction needed.
    # Auth is header-based (Bearer token), not cookies, so wildcard is safe here.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── Exception handlers ────────────────────────────────────────────────────

    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail, "code": exc.code},
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error on %s %s", request.method, request.url)
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error", "code": "internal_error"},
        )

    # ── Routes ────────────────────────────────────────────────────────────────

    @app.get("/health", tags=["infra"])
    async def health() -> dict:
        return {"status": "ok"}

    app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
    app.include_router(calls_router.router, prefix="/api/auth", tags=["calls"])
    app.include_router(users_router.router, prefix="/api/users", tags=["users"])
    app.include_router(contacts_router.router, prefix="/api/contacts", tags=["contacts"])
    app.include_router(conversations_router.router, prefix="/api/conversations", tags=["conversations"])
    app.include_router(messages_router.router, prefix="/api/messages", tags=["messages"])
    app.include_router(media_router.router, prefix="/api/media", tags=["media"])

    return app


app = create_app()
