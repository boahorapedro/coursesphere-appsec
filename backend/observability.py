import json
import logging
import os
import sys
import time
import uuid
from datetime import datetime, timezone

from flask import Flask, Response, g, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

REQUESTS = Counter(
    "http_requests_total", "Total de requisições HTTP", ["method", "route", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latência das requisições HTTP, em segundos",
    ["route"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

INTERNAL_PATHS = {"/health", "/metrics"}


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, timezone.utc).isoformat(
                timespec="milliseconds"
            ),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "instance": os.environ.get("HOSTNAME", "unknown"),
        }
        payload.update(getattr(record, "http", {}))
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def init_observability(app: Flask) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    app.logger.handlers.clear()

    logging.getLogger("werkzeug").setLevel(logging.WARNING)

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()
        g.request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex

    @app.after_request
    def _record(response):
        if request.path in INTERNAL_PATHS:
            return response
        duration = time.perf_counter() - g.get("start", time.perf_counter())
        route = request.url_rule.rule if request.url_rule else "unmatched"
        REQUESTS.labels(request.method, route, str(response.status_code)).inc()
        LATENCY.labels(route).observe(duration)
        app.logger.info(
            "request",
            extra={
                "http": {
                    "request_id": g.get("request_id"),
                    "method": request.method,
                    "path": request.path,
                    "route": route,
                    "status": response.status_code,
                    "duration_ms": round(duration * 1000, 2),
                    "forwarded_for": request.headers.get("X-Forwarded-For"),
                }
            },
        )
        response.headers["X-Request-ID"] = g.get("request_id", "")
        return response

    @app.get("/health")
    def health():
        return {"status": "ok"}, 200

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), content_type=CONTENT_TYPE_LATEST)