"""
Lumin FastAPI application factory.
"""
import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

import redis.asyncio as aioredis
from fastapi import FastAPI, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import text

from app.config import settings
from app.db import engine
from app.dependencies import client_ip
from app.metrics import MetricsMiddleware, metrics
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
from app.routers import settings as settings_router
from app.routers import support as support_router
from app.routers import users as users_router
from app.utils.exceptions import AppError
from app.utils.storage import ensure_media_dirs

logger = logging.getLogger(__name__)

templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent / "templates"))


class BodySizeLimitMiddleware:
    """
    Reject oversized request bodies up front using the Content-Length header.

    A pure-ASGI middleware so it runs before the body is read into memory. This
    catches the common DoS shape (a declared multi-gigabyte payload) cheaply;
    a chunked request without Content-Length still streams, but FastAPI's
    per-endpoint upload size checks remain the backstop there.
    """

    def __init__(self, app, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] == "http":
            for name, value in scope.get("headers", []):
                if name == b"content-length":
                    try:
                        declared = int(value)
                    except ValueError:
                        break
                    if declared > self.max_bytes:
                        response = JSONResponse(
                            status_code=413,
                            content={
                                "detail": "Request body too large",
                                "code": "file_too_large",
                            },
                        )
                        await response(scope, receive, send)
                        return
                    break
        await self.app(scope, receive, send)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    # ── Startup ──────────────────────────────────────────────────────────────
    redis_client = aioredis.from_url(
        settings.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
    )
    # Bounded ping so a slow/unreachable Redis fails startup fast instead of
    # hanging the boot indefinitely.
    await asyncio.wait_for(redis_client.ping(), timeout=5.0)
    app.state.redis = redis_client
    logger.info("Redis connected at %s", settings.REDIS_URL)

    # Loud warning if the deployment is still running on placeholder domains —
    # CORS and TURN silently break when DOMAIN/TURN_HOST are left as examples.
    if "example.com" in (settings.DOMAIN, settings.TURN_HOST) or \
            settings.DOMAIN.endswith("example.com") or \
            settings.TURN_HOST.endswith("example.com"):
        logger.warning(
            "DOMAIN=%r / TURN_HOST=%r still use placeholder 'example.com' "
            "values — CORS and TURN will not work until these are set.",
            settings.DOMAIN,
            settings.TURN_HOST,
        )

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

    # ── Request body ceiling ──────────────────────────────────────────────────
    app.add_middleware(
        BodySizeLimitMiddleware,
        max_bytes=settings.MAX_REQUEST_BODY_MB * 1024 * 1024,
    )

    # ── HTTP metrics ──────────────────────────────────────────────────────────
    # Added last → outermost, so recorded latency spans the whole chain
    # (including the body-size guard and CORS).
    app.add_middleware(MetricsMiddleware)

    # ── CORS ──────────────────────────────────────────────────────────────────
    # Mobile clients don't enforce CORS, so the only callers this matters for
    # are browser-based tools (Swagger docs, ad-hoc Postman browser plugins).
    # Allow just the production HTTPS origin with the verbs we actually use —
    # cuts down on the surface a malicious page could probe through a browser.
    _allowed_origins = [f"https://{settings.DOMAIN}"]
    # In DEBUG, also accept localhost on any port so dev tools (Swagger on a
    # random port, a local web build on :3000, etc.) can hit the API without
    # CORS friction. The regex covers localhost / 127.0.0.1 with or without a port.
    _origin_regex = (
        r"^http://(localhost|127\.0\.0\.1)(:\d+)?$" if settings.DEBUG else None
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_allowed_origins,
        allow_origin_regex=_origin_regex,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
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

        The detailed health report (topology + environment) must never be
        served to external callers unauthenticated.
        """
        ip = client_ip(request)
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

    @app.get("/metrics", tags=["infra"])
    async def metrics(request: Request):
        """
        Prometheus exposition of DB connection-pool saturation + liveness.

        Internal-only (same RFC-1918 / localhost gate as the detailed health
        report) — pool internals shouldn't be world-readable, and a public
        /metrics is a common information leak. External callers get a 404 so
        the endpoint isn't even advertised. Hand-rolled text format keeps this
        dependency-free (no prometheus_client needed).
        """
        if not _is_internal(request):
            return JSONResponse(status_code=404, content={"detail": "Not found"})

        # The async engine wraps a sync engine whose pool exposes the counters.
        pool = engine.sync_engine.pool

        def _stat(fn: str) -> int:
            method = getattr(pool, fn, None)
            try:
                return int(method()) if callable(method) else -1
            except Exception:
                return -1

        # Redis liveness (bounded so a stuck Redis can't hang a scrape).
        redis_up = 0
        try:
            await asyncio.wait_for(request.app.state.redis.ping(), timeout=1.0)
            redis_up = 1
        except Exception:
            redis_up = 0

        version = app.version
        lines = [
            "# HELP lumin_app_info Application metadata.",
            "# TYPE lumin_app_info gauge",
            f'lumin_app_info{{version="{version}"}} 1',
            "# HELP lumin_db_pool_size Configured base pool size.",
            "# TYPE lumin_db_pool_size gauge",
            f"lumin_db_pool_size {_stat('size')}",
            "# HELP lumin_db_pool_checked_out Connections currently in use.",
            "# TYPE lumin_db_pool_checked_out gauge",
            f"lumin_db_pool_checked_out {_stat('checkedout')}",
            "# HELP lumin_db_pool_checked_in Idle connections available in the pool.",
            "# TYPE lumin_db_pool_checked_in gauge",
            f"lumin_db_pool_checked_in {_stat('checkedin')}",
            "# HELP lumin_db_pool_overflow Overflow connections beyond the base size.",
            "# TYPE lumin_db_pool_overflow gauge",
            f"lumin_db_pool_overflow {_stat('overflow')}",
            "# HELP lumin_db_pool_max_overflow Configured max overflow.",
            "# TYPE lumin_db_pool_max_overflow gauge",
            f"lumin_db_pool_max_overflow {settings.DB_MAX_OVERFLOW}",
            "# HELP lumin_redis_up 1 if Redis answered a ping, else 0.",
            "# TYPE lumin_redis_up gauge",
            f"lumin_redis_up {redis_up}",
        ]
        # Append per-request count + latency histogram.
        lines += metrics.render()
        return Response(
            content="\n".join(lines) + "\n",
            media_type="text/plain; version=0.0.4; charset=utf-8",
        )

    app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
    app.include_router(calls_router.router, prefix="/api/calls", tags=["calls"])
    app.include_router(users_router.router, prefix="/api/users", tags=["users"])
    app.include_router(contacts_router.router, prefix="/api/contacts", tags=["contacts"])
    app.include_router(conversations_router.router, prefix="/api/conversations", tags=["conversations"])
    app.include_router(messages_router.router, prefix="/api/messages", tags=["messages"])
    app.include_router(media_router.router, prefix="/api/media", tags=["media"])
    app.include_router(
        settings_router.router, prefix="/api/users/me/settings", tags=["settings"]
    )
    app.include_router(support_router.router, prefix="/api/support", tags=["support"])

    return app


app = create_app()
