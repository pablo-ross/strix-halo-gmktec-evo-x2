import json
import os

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse

BACKEND_URL = os.getenv("BACKEND_URL", "http://10.0.0.60").rstrip("/")
_raw_tokens = os.getenv("API_TOKENS", "")
API_TOKENS = {t.strip() for t in _raw_tokens.split(",") if t.strip()}

# Caps how many requests are forwarded to the backend at once. The backend is a
# single GPU (one llama-server slot pool per model, all sharing one machine's
# compute) — without this, every caller's request gets accepted and queued
# invisibly inside llama-server instead of failing fast. Default of 4 matches
# the smallest currently-configured --parallel slot count (Bielik-11B).
#
# A plain counter (not asyncio.Semaphore) on purpose: this process is single
# worker/single-threaded, and nothing awaits between the check and increment
# below, so it's already atomic — no need for a Semaphore, whose non-blocking
# acquire via wait_for(..., timeout=0) can spuriously time out even when a
# permit is free (a known asyncio gotcha).
MAX_CONCURRENT_REQUESTS = int(os.getenv("MAX_CONCURRENT_REQUESTS", "4"))
_inflight_count = 0


def _try_acquire() -> bool:
    global _inflight_count
    if _inflight_count >= MAX_CONCURRENT_REQUESTS:
        return False
    _inflight_count += 1
    return True


def _release() -> None:
    global _inflight_count
    _inflight_count -= 1


# Lets old/retired model names in client requests keep working after a
# backend swap, without having to update every client.
# Format: "old-name-1:new-name-1,old-name-2:new-name-2"
_raw_aliases = os.getenv("MODEL_ALIASES", "")
MODEL_ALIASES = dict(
    pair.split(":", 1) for pair in _raw_aliases.split(",") if ":" in pair
)

app = FastAPI(title="LLM API Relay")

_HOP_BY_HOP = frozenset(
    {"transfer-encoding", "connection", "keep-alive", "te", "trailers", "upgrade"}
)


async def verify_token(request: Request):
    if not API_TOKENS:
        raise HTTPException(500, "No API tokens configured on the relay")
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "Unauthorized: Bearer token required")
    if auth[7:] not in API_TOKENS:
        raise HTTPException(403, "Forbidden: invalid token")


@app.get("/health")
async def health():
    return {"status": "ok", "backend": BACKEND_URL}


@app.api_route(
    "/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
)
async def proxy(path: str, request: Request, _=Depends(verify_token)):
    if not _try_acquire():
        raise HTTPException(
            429,
            f"Server busy: {MAX_CONCURRENT_REQUESTS} requests already in flight, try again shortly",
        )
    try:
        return await _proxy(path, request)
    except BaseException:
        _release()
        raise


async def _proxy(path: str, request: Request):
    # Caller releases _inflight once this returns: immediately on the
    # non-streaming path below, or when the SSE generator finishes for
    # streaming responses (a real in-flight request until the last byte).
    url = f"{BACKEND_URL}/{path}"
    body = await request.body()

    if MODEL_ALIASES and "application/json" in request.headers.get("content-type", ""):
        try:
            payload = json.loads(body)
        except ValueError:
            payload = None
        if isinstance(payload, dict) and payload.get("model") in MODEL_ALIASES:
            payload["model"] = MODEL_ALIASES[payload["model"]]
            body = json.dumps(payload).encode()

    # Strip headers that must not be forwarded
    forward_headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in ("host", "authorization", "content-length")
    }

    client = httpx.AsyncClient(timeout=600.0)
    req = client.build_request(
        method=request.method,
        url=url,
        headers=forward_headers,
        content=body,
        params=dict(request.query_params),
    )
    resp = await client.send(req, stream=True)

    is_sse = "text/event-stream" in resp.headers.get("content-type", "")

    if is_sse:

        async def _stream():
            try:
                async for chunk in resp.aiter_bytes():
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()
                _release()

        return StreamingResponse(
            _stream(),
            status_code=resp.status_code,
            media_type="text/event-stream",
        )

    try:
        content = await resp.aread()
    finally:
        await resp.aclose()
        await client.aclose()

    response_headers = {
        k: v for k, v in resp.headers.items() if k.lower() not in _HOP_BY_HOP
    }
    _release()
    return Response(
        content=content,
        status_code=resp.status_code,
        headers=response_headers,
    )
