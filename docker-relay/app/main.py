import json
import os

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response, StreamingResponse

BACKEND_URL = os.getenv("BACKEND_URL", "http://10.0.0.60").rstrip("/")
_raw_tokens = os.getenv("API_TOKENS", "")
API_TOKENS = {t.strip() for t in _raw_tokens.split(",") if t.strip()}

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

        return StreamingResponse(
            _stream(),
            status_code=resp.status_code,
            media_type="text/event-stream",
        )

    content = await resp.aread()
    await resp.aclose()
    await client.aclose()

    response_headers = {
        k: v for k, v in resp.headers.items() if k.lower() not in _HOP_BY_HOP
    }
    return Response(
        content=content,
        status_code=resp.status_code,
        headers=response_headers,
    )
