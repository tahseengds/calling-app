"""
Lumin FastAPI application factory.
"""
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

import redis.asyncio as aioredis
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import text

from app.config import settings
from app.db import engine
from app.services.health_service import (
    collect_health,
    wants_detailed_report,
    wants_json_response,
)
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

templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent / "templates"))


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
        title="Lumin API",
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
        # Log 401/403 with the specific code+detail so we can diagnose
        # token-rejection issues from docker logs. Other AppErrors stay
        # quiet (they're routine business-logic responses).
        if exc.status_code in (401, 403):
            logger.warning(
                "%s %s → %d %s: %s",
                request.method,
                request.url.path,
                exc.status_code,
                exc.code,
                exc.detail,
            )
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

    def _is_internal(request: Request) -> bool:
        """
        Returns True only for requests that originate from localhost or a
        private RFC-1918 / Docker-internal address.

        Nginx sets X-Real-IP; fall back to the raw ASGI client IP.
        The detailed health report (topology + environment) must never be
        served to external callers unauthenticated.
        """
        ip = request.headers.get("x-real-ip") or (
            request.client.host if request.client else ""
        )
        return ip in ("127.0.0.1", "::1", "localhost") or ip.startswith(
            ("10.", "172.16.", "172.17.", "172.18.", "172.19.", "172.20.",
             "172.21.", "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
             "172.27.", "172.28.", "172.29.", "172.30.", "172.31.", "192.168.")
        )

    @app.get("/health", tags=["infra"])
    async def health(
        request: Request,
        format: str | None = Query(default=None, alias="format"),
        detailed: bool = Query(default=False, alias="detailed"),
    ):
        accept = request.headers.get("accept")
        # Detailed report exposes internal topology — restrict to internal callers.
        if not wants_detailed_report(accept, format, detailed) or not _is_internal(request):
            return JSONResponse(content={"status": "ok"})
        report = await collect_health(request.app.state.redis, engine)
        if wants_json_response(accept, format):
            return JSONResponse(
                content=report.to_json(),
                status_code=report.http_status,
            )
        return templates.TemplateResponse(
            request=request,
            name="health.html",
            context={"report": report},
            status_code=report.http_status,
        )

    app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
    app.include_router(calls_router.router, prefix="/api/calls", tags=["calls"])
    app.include_router(users_router.router, prefix="/api/users", tags=["users"])
    app.include_router(contacts_router.router, prefix="/api/contacts", tags=["contacts"])
    app.include_router(conversations_router.router, prefix="/api/conversations", tags=["conversations"])
    app.include_router(messages_router.router, prefix="/api/messages", tags=["messages"])
    app.include_router(media_router.router, prefix="/api/media", tags=["media"])

    return app


app = create_app()
