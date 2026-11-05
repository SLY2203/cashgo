from fastapi import FastAPI

from app.api.v1 import (admin, agent_portal, agents, auth, payments,
                        remittances, scan, wallets)

app = FastAPI(title="CashGo API", version="0.2.0")

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
