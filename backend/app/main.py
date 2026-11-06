import time
from collections import defaultdict, deque

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.v1 import (admin, agent_portal, agents, auth, payments,
                        remittances, scan, wallets)

app = FastAPI(title="CashGo API", version="0.2.0")


# ---- lightweight rate limiting ---------------------------------------------
# Per-IP sliding window. Tighter on OTP/auth + money endpoints.
_BUCKETS: dict[tuple, deque] = defaultdict(deque)
_RULES = [
    ("/api/v1/auth/otp", 5, 60),       # 5 OTP requests/min
    ("/api/v1/remittances/transfer/", 20, 60),
    ("/api/v1/scan/", 30, 60),
    ("/api/v1/agent/", 30, 60),
    ("/api/v1/", 120, 60),             # global default
]


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    ip = request.client.host if request.client else "?"
    path = request.url.path
    limit, window = next(
        ((l, w) for p, l, w in _RULES if path.startswith(p)),
        (0, 0))
    if limit:
        key = (ip, path if limit < 100 else "*")
        now = time.time()
        q = _BUCKETS[key]
        while q and now - q[0] > window:
            q.popleft()
        if len(q) >= limit:
            return JSONResponse(
                {"detail": "Rate limit exceeded — slow down"}, status_code=429)
        q.append(now)
    return await call_next(request)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(remittances.router, prefix="/api/v1")
app.include_router(agents.router, prefix="/api/v1")
app.include_router(wallets.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(scan.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(admin.pages)
app.include_router(agent_portal.router, prefix="/api/v1")
app.include_router(agent_portal.pages)


@app.get("/health")
def health():
    return {"status": "ok"}
