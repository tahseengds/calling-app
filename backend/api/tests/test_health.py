"""Tests for /health JSON probes and HTML dashboard."""
import pytest
from httpx import AsyncClient

from app.services import health_service
from app.services.health_service import CheckStatus, HealthCheck


@pytest.fixture(autouse=True)
def mock_external_health_checks(monkeypatch: pytest.MonkeyPatch) -> None:
    """Avoid Docker-only hostnames (signaling, TURN) during unit tests."""

    async def _ok_signaling() -> HealthCheck:
        return HealthCheck(
            name="Signaling",
            status=CheckStatus.OK,
            message="mock",
            latency_ms=1.0,
            critical=True,
        )

    async def _ok_domain_tls() -> HealthCheck:
        return HealthCheck(
            name="Domain & TLS",
            status=CheckStatus.OK,
            message="mock",
            critical=False,
        )

    async def _ok_turn() -> HealthCheck:
        return HealthCheck(
            name="TURN (Coturn)",
            status=CheckStatus.OK,
            message="mock",
            critical=False,
        )

    async def _ok_turns() -> HealthCheck:
        return HealthCheck(
            name="TURNS (TLS)",
            status=CheckStatus.WARN,
            message="mock",
            critical=False,
        )

    monkeypatch.setattr(health_service, "_check_signaling", _ok_signaling)
    monkeypatch.setattr(health_service, "_check_domain_tls", _ok_domain_tls)
    monkeypatch.setattr(health_service, "_check_turn", _ok_turn)
    monkeypatch.setattr(health_service, "_check_turns", _ok_turns)


@pytest.mark.asyncio
async def test_health_probe_is_lightweight(client: AsyncClient) -> None:
    """Bots and monitors must not trigger expensive checks."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}

    resp2 = await client.get("/health?format=json")
    assert resp2.status_code == 200
    assert resp2.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_health_detailed_json(client: AsyncClient) -> None:
    resp = await client.get("/health?detailed=1")
    assert resp.status_code in (200, 503)
    data = resp.json()
    assert data["status"] in ("ok", "degraded", "down")
    assert isinstance(data["checks"], list)
    assert len(data["checks"]) >= 4
    assert "generated_at" in data
    assert "environment" in data


@pytest.mark.asyncio
async def test_health_html_dashboard(client: AsyncClient) -> None:
    resp = await client.get(
        "/health",
        headers={"Accept": "text/html"},
    )
    assert resp.status_code in (200, 503)
    assert "text/html" in resp.headers["content-type"]
    body = resp.text
    assert "Lumin" in body
    assert "Services" in body


@pytest.mark.asyncio
async def test_health_full_format_json(client: AsyncClient) -> None:
    resp = await client.get("/health?format=full")
    assert resp.status_code in (200, 503)
    assert "checks" in resp.json()
