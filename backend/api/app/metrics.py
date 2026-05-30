"""
Lightweight, dependency-free HTTP metrics.

A process-local registry plus a pure-ASGI middleware that records a request
count and a latency histogram for every HTTP request. Rendered in Prometheus
text format by the /metrics endpoint (alongside the DB-pool gauges).

Labels are kept to (method, status) only — deliberately NOT the URL path — so
cardinality stays bounded (paths contain UUIDs, which would explode the series
count). The histogram buckets are cumulative per Prometheus convention.
"""
from __future__ import annotations

import threading
import time

# Cumulative latency buckets in seconds (the "+Inf" bucket is implicit = count).
LATENCY_BUCKETS: tuple[float, ...] = (
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
)


class HttpMetrics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        # (method, status) -> count
        self.requests_total: dict[tuple[str, int], int] = {}
        # method -> cumulative bucket counts (one slot per LATENCY_BUCKETS entry)
        self.duration_buckets: dict[str, list[int]] = {}
        self.duration_sum: dict[str, float] = {}
        self.duration_count: dict[str, int] = {}

    def observe(self, method: str, status: int, elapsed: float) -> None:
        with self._lock:
            key = (method, status)
            self.requests_total[key] = self.requests_total.get(key, 0) + 1

            buckets = self.duration_buckets.setdefault(
                method, [0] * len(LATENCY_BUCKETS)
            )
            # Increment every bucket whose upper bound the sample falls under,
            # which makes each slot already hold the cumulative "<= le" count.
            for i, bound in enumerate(LATENCY_BUCKETS):
                if elapsed <= bound:
                    buckets[i] += 1
            self.duration_sum[method] = self.duration_sum.get(method, 0.0) + elapsed
            self.duration_count[method] = self.duration_count.get(method, 0) + 1

    def render(self) -> list[str]:
        """Return Prometheus exposition lines for the HTTP metrics."""
        with self._lock:
            requests = sorted(self.requests_total.items())
            methods = sorted(self.duration_count.keys())
            buckets = {m: list(self.duration_buckets.get(m, [])) for m in methods}
            sums = dict(self.duration_sum)
            counts = dict(self.duration_count)

        lines: list[str] = [
            "# HELP lumin_http_requests_total Total HTTP requests by method and status.",
            "# TYPE lumin_http_requests_total counter",
        ]
        for (method, status), count in requests:
            lines.append(
                f'lumin_http_requests_total{{method="{method}",status="{status}"}} {count}'
            )

        lines += [
            "# HELP lumin_http_request_duration_seconds HTTP request latency by method.",
            "# TYPE lumin_http_request_duration_seconds histogram",
        ]
        for method in methods:
            bcounts = buckets[method]
            total = counts.get(method, 0)
            for i, bound in enumerate(LATENCY_BUCKETS):
                le = repr(bound)
                lines.append(
                    f'lumin_http_request_duration_seconds_bucket'
                    f'{{method="{method}",le="{le}"}} {bcounts[i]}'
                )
            lines.append(
                f'lumin_http_request_duration_seconds_bucket'
                f'{{method="{method}",le="+Inf"}} {total}'
            )
            lines.append(
                f'lumin_http_request_duration_seconds_sum'
                f'{{method="{method}"}} {sums.get(method, 0.0)}'
            )
            lines.append(
                f'lumin_http_request_duration_seconds_count'
                f'{{method="{method}"}} {total}'
            )
        return lines


# Process-wide singleton.
metrics = HttpMetrics()


class MetricsMiddleware:
    """Pure-ASGI middleware that times each request and records it in [metrics].

    Add it outermost so the measured latency covers the whole handling chain.
    The /metrics scrape itself is excluded to avoid self-measurement noise.
    """

    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "UNKNOWN")
        path = scope.get("path", "")
        start = time.perf_counter()
        status_code = 500

        async def send_wrapper(message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            if path != "/metrics":
                metrics.observe(method, status_code, time.perf_counter() - start)
