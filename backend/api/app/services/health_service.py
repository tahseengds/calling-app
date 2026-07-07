"""
Aggregate health checks for /health (JSON probes and HTML dashboard).
"""
from __future__ import annotations

import asyncio
import re
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
import redis.asyncio as aioredis
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine

from app.config import settings
from app.utils.storage import ensure_media_dirs

_SIGNALING_HEALTH_URL = "http://signaling:8001/health"
_NGINX_INTERNAL_HEALTH = "http://nginx/health?format=json"
_PLACEHOLDER_RE = re.compile(r"REPLACE_WITH|CHANGE_ME|your-", re.I)
_IPV4_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"
)


class CheckStatus(str, Enum):
    OK = "ok"
    WARN = "warn"
    ERROR = "error"


class OverallStatus(str, Enum):
    OK = "ok"
    DEGRADED = "degraded"
    DOWN = "down"


@dataclass
class HealthCheck:
    name: str
    status: CheckStatus
    message: str
    latency_ms: float | None = None
    critical: bool = True

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status.value,
            "message": self.message,
            "latency_ms": self.latency_ms,
            "critical": self.critical,
        }


@dataclass
class HealthReport:
    status: OverallStatus
    checks: list[HealthCheck] = field(default_factory=list)
    attention: list[str] = field(default_factory=list)
    environment: dict[str, str] = field(default_factory=dict)
    generated_at: str = ""

    @property
    def http_status(self) -> int:
        return 503 if self.status == OverallStatus.DOWN else 200

    def to_json(self) -> dict[str, Any]:
        return {
            "status": self.status.value,
            "checks": [c.to_dict() for c in self.checks],
            "attention": self.attention,
            "environment": self.environment,
            "generated_at": self.generated_at,
        }


def wants_json_response(accept: str | None, format_param: str | None) -> bool:
    """Whether a detailed /health response should be JSON (vs HTML dashboard)."""
    if format_param == "html":
        return False
    if format_param in ("json", "full", "detailed"):
        return True
    if not accept:
        return True
    lowered = accept.lower()
    if "text/html" in lowered and "application/json" not in lowered:
        return False
    if "application/json" in lowered:
        return True
    return True


def wants_detailed_report(accept: str | None, format_param: str | None, detailed: bool) -> bool:
    """
    Full health dashboard / JSON report — expensive (DB, Redis, HTTP, TCP probes).

    Lightweight {"status":"ok"} is used for probes, bots, and deploy scripts.
    """
    if detailed:
        return True
    if format_param in ("full", "detailed"):
        return True
    if format_param == "html":
        return True
    if not accept:
        return False
    lowered = accept.lower()
    return "text/html" in lowered


def _is_placeholder(value: str) -> bool:
    return not value.strip() or bool(_PLACEHOLDER_RE.search(value))


def _domain_is_ip(domain: str) -> bool:
    return bool(_IPV4_RE.match(domain.strip()))


async def _timed(coro) -> tuple[Any, float]:
    start = time.perf_counter()
    result = await coro
    return result, (time.perf_counter() - start) * 1000


async def _check_postgres(engine: AsyncEngine) -> HealthCheck:
    try:
        async def _ping():
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))

        _, latency = await _timed(_ping())
        return HealthCheck(
            name="PostgreSQL",
            status=CheckStatus.OK,
            message="Connected",
            latency_ms=round(latency, 1),
            critical=True,
        )
    except Exception as exc:
        return HealthCheck(
            name="PostgreSQL",
            status=CheckStatus.ERROR,
            message=f"Connection failed ({type(exc).__name__})",
            critical=True,
        )


async def _check_redis(redis_client: aioredis.Redis) -> HealthCheck:
    try:
        _, latency = await _timed(redis_client.ping())
        return HealthCheck(
            name="Redis",
            status=CheckStatus.OK,
            message="PONG",
            latency_ms=round(latency, 1),
            critical=True,
        )
    except Exception as exc:
        return HealthCheck(
            name="Redis",
            status=CheckStatus.ERROR,
            message=f"Connection failed ({type(exc).__name__})",
            critical=True,
        )


async def _check_media_storage() -> HealthCheck:
    try:
        ensure_media_dirs()
        base = Path(settings.MEDIA_BASE_PATH)
        probe = base / f".health_probe_{uuid.uuid4().hex}"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        return HealthCheck(
            name="Media storage",
            status=CheckStatus.OK,
            message=f"Writable at {settings.MEDIA_BASE_PATH}",
            critical=True,
        )
    except Exception as exc:
        return HealthCheck(
            name="Media storage",
            status=CheckStatus.ERROR,
            message=f"Storage check failed ({type(exc).__name__})",
            critical=True,
        )


async def _check_signaling() -> HealthCheck:
    try:
        async def _fetch():
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(_SIGNALING_HEALTH_URL)
                resp.raise_for_status()
                return resp.json()

        data, latency = await _timed(_fetch())
        detail = data.get("status", "ok") if isinstance(data, dict) else "ok"
        return HealthCheck(
            name="Signaling",
            status=CheckStatus.OK,
            message=f"WebSocket server ({detail})",
            latency_ms=round(latency, 1),
            critical=True,
        )
    except Exception as exc:
        return HealthCheck(
            name="Signaling",
            status=CheckStatus.ERROR,
            message=f"Unreachable ({type(exc).__name__})",
            critical=True,
        )


async def _check_firebase() -> HealthCheck:
    project_ok = not _is_placeholder(settings.FIREBASE_PROJECT_ID)
    creds_path = Path(settings.FIREBASE_SERVICE_ACCOUNT_PATH)
    file_ok = creds_path.is_file()
    if project_ok and file_ok:
        return HealthCheck(
            name="Firebase (FCM)",
            status=CheckStatus.OK,
            message=f"Configured ({settings.FIREBASE_PROJECT_ID})",
            critical=False,
        )
    parts = []
    if not project_ok:
        parts.append("FIREBASE_PROJECT_ID not set")
    if not file_ok:
        parts.append(f"missing {settings.FIREBASE_SERVICE_ACCOUNT_PATH}")
    return HealthCheck(
        name="Firebase (FCM)",
        status=CheckStatus.WARN,
        message="; ".join(parts) or "Not configured",
        critical=False,
    )


async def _check_domain_tls() -> HealthCheck:
    domain = settings.DOMAIN.strip()
    if _domain_is_ip(domain):
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.WARN,
            message=f"DOMAIN is an IP ({domain}) — use a hostname for HTTPS",
            critical=False,
        )
    if settings.MEDIA_URL_SCHEME.lower() != "https":
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.WARN,
            message="MEDIA_URL_SCHEME is not https",
            critical=False,
        )
    url = f"https://{domain}/health?format=json"
    try:
        async with httpx.AsyncClient(timeout=5.0, verify=True) as client:
            resp = await client.get(url)
        if resp.status_code == 200:
            return HealthCheck(
                name="Domain & TLS",
                status=CheckStatus.OK,
                message=f"HTTPS reachable at {domain}",
                critical=False,
            )
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.WARN,
            message=f"HTTPS returned {resp.status_code}",
            critical=False,
        )
    except (httpx.TimeoutException, httpx.ConnectError):
        # Hairpin NAT: containers often cannot reach the server's public HTTPS URL.
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    _NGINX_INTERNAL_HEALTH,
                    headers={"Host": domain},
                    follow_redirects=False,
                )
            if resp.status_code == 200 or (
                resp.status_code in (301, 308)
                and resp.headers.get("location", "").startswith("https://")
            ):
                return HealthCheck(
                    name="Domain & TLS",
                    status=CheckStatus.OK,
                    message=(
                        f"HTTPS active at {domain} "
                        "(nginx redirects HTTP→HTTPS; public hairpin unavailable from container)"
                    ),
                    critical=False,
                )
        except Exception:
            pass
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.WARN,
            message=(
                f"Could not probe https://{domain} from this container "
                "(often normal on VPS; verify in a browser)"
            ),
            critical=False,
        )
    except Exception as exc:
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.WARN,
            message=f"HTTPS check failed: {exc}",
            critical=False,
        )


async def _tcp_probe(host: str, port: int, timeout: float = 3.0) -> tuple[bool, str]:
    try:
        loop = asyncio.get_running_loop()
        await asyncio.wait_for(
            loop.run_in_executor(
                None,
                lambda: _sync_tcp_connect(host, port, timeout),
            ),
            timeout=timeout + 1,
        )
        return True, "Port open"
    except Exception as exc:
        return False, str(exc)


def _sync_tcp_connect(host: str, port: int, timeout: float) -> None:
    import socket

    with socket.create_connection((host, port), timeout=timeout):
        pass


async def _check_turn() -> HealthCheck:
    host = settings.TURN_HOST.strip()
    if not host:
        return HealthCheck(
            name="TURN (Coturn)",
            status=CheckStatus.WARN,
            message="TURN_HOST not set",
            critical=False,
        )
    ok, detail = await _tcp_probe(host, 3478)
    if ok:
        return HealthCheck(
            name="TURN (Coturn)",
            status=CheckStatus.OK,
            message=f"STUN/TURN reachable on {host}:3478",
            critical=False,
        )
    return HealthCheck(
        name="TURN (Coturn)",
        status=CheckStatus.WARN,
        message=f"{host}:3478 — {detail}",
        critical=False,
    )


async def _check_turns() -> HealthCheck:
    host = settings.TURN_HOST.strip()
    if not host or _domain_is_ip(host):
        return HealthCheck(
            name="TURNS (TLS)",
            status=CheckStatus.WARN,
            message="Requires a domain and Let's Encrypt cert (port 5349)",
            critical=False,
        )
    ok, detail = await _tcp_probe(host, 5349)
    if ok:
        return HealthCheck(
            name="TURNS (TLS)",
            status=CheckStatus.OK,
            message=f"Encrypted TURN on {host}:5349",
            critical=False,
        )
    return HealthCheck(
        name="TURNS (TLS)",
        status=CheckStatus.WARN,
        message=(
            f"{host}:5349 — {detail}. "
            "If certs exist, run coturn/install.sh (turnserver cannot read /etc/letsencrypt directly)."
        ),
        critical=False,
    )


def _build_environment() -> dict[str, str]:
    redis_host = settings.REDIS_URL
    try:
        parsed = urlparse(settings.REDIS_URL)
        redis_host = parsed.hostname or settings.REDIS_URL
    except Exception:
        pass
    return {
        "app_env": settings.APP_ENV,
        "domain": settings.DOMAIN,
        "turn_host": settings.TURN_HOST,
        "media_url_scheme": settings.MEDIA_URL_SCHEME,
        "postgres_db": settings.POSTGRES_DB,
        "redis_host": str(redis_host),
        "debug": str(settings.DEBUG).lower(),
    }


def _build_attention(checks: list[HealthCheck]) -> list[str]:
    items: list[str] = []
    domain = settings.DOMAIN.strip()

    if _domain_is_ip(domain):
        items.append(
            f"DOMAIN is still an IP ({domain}) — point a hostname at this server "
            "and run deploy/issue-cert.sh for HTTPS."
        )
    if settings.MEDIA_URL_SCHEME.lower() == "http" and settings.APP_ENV == "production":
        items.append(
            "MEDIA_URL_SCHEME=http — signed media URLs are not HTTPS. "
            "Set https after TLS is enabled."
        )
    if _is_placeholder(settings.FIREBASE_PROJECT_ID) or not Path(
        settings.FIREBASE_SERVICE_ACCOUNT_PATH
    ).is_file():
        items.append(
            "Firebase not configured — push notifications are disabled."
        )

    for check in checks:
        if check.name == "TURNS (TLS)" and check.status == CheckStatus.WARN:
            if "Requires a domain" in check.message:
                items.append(
                    "TURNS (port 5349) needs a domain and Let's Encrypt certificate."
                )
            else:
                items.append(
                    "TURNS (port 5349) is not listening — encrypted calls may fall back to "
                    "plain TURN on 3478. Re-run coturn/install.sh after TLS is issued."
                )
            break
        if check.name == "TURN (Coturn)" and check.status == CheckStatus.WARN:
            items.append(f"TURN/STUN may be unreachable: {check.message}")
        if check.name == "Domain & TLS" and check.status == CheckStatus.WARN:
            items.append(check.message)

    # Deduplicate while preserving order
    seen: set[str] = set()
    unique: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            unique.append(item)
    return unique


def _derive_overall(checks: list[HealthCheck], attention: list[str]) -> OverallStatus:
    if any(c.critical and c.status == CheckStatus.ERROR for c in checks):
        return OverallStatus.DOWN
    if attention or any(c.status == CheckStatus.WARN for c in checks):
        return OverallStatus.DEGRADED
    return OverallStatus.OK


async def collect_health(
    redis_client: aioredis.Redis,
    engine: AsyncEngine,
) -> HealthReport:
    critical = await asyncio.gather(
        _check_postgres(engine),
        _check_redis(redis_client),
        _check_media_storage(),
        _check_signaling(),
    )
    optional = await asyncio.gather(
        _check_firebase(),
        _check_domain_tls(),
        _check_turn(),
        _check_turns(),
    )
    checks = list(critical) + list(optional)
    attention = _build_attention(checks)
    status = _derive_overall(checks, attention)
    return HealthReport(
        status=status,
        checks=checks,
        attention=attention,
        environment=_build_environment(),
        generated_at=datetime.now(timezone.utc).isoformat(),
    )
