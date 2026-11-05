"""Admin API + minimal web dashboard.

The dashboard HTML itself is served unauthenticated (it's a static shell);
every data call it makes requires the X-Admin-Key header, which the page
stores in localStorage after you paste it once.
"""
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_admin
from app.models import CorridorFeeConfig, Transaction, TxnStatus, User
from app.schemas import FeeConfigIn, FeeConfigOut

# ---- protected JSON API ------------------------------------------------------
router = APIRouter(prefix="/admin", tags=["admin"],
                   dependencies=[Depends(require_admin)])


@router.post("/fees/", response_model=FeeConfigOut, status_code=201)
def create_fee_config(body: FeeConfigIn, db: Session = Depends(get_db)):
    cfg = CorridorFeeConfig(**{k: (v.upper() if isinstance(v, str)
                                   and k.endswith(("country", "currency")) else v)
                               for k, v in body.model_dump().items()})
    db.add(cfg)
    db.commit()
    db.refresh(cfg)
    return cfg


@router.get("/fees/", response_model=list[FeeConfigOut])
def list_fee_configs(db: Session = Depends(get_db)):
    return list(db.execute(select(CorridorFeeConfig)).scalars())


@router.patch("/fees/{config_id}", response_model=FeeConfigOut)
def update_fee_config(config_id: UUID, body: FeeConfigIn, db: Session = Depends(get_db)):
    cfg = db.get(CorridorFeeConfig, config_id)
    if cfg is None:
        raise HTTPException(404, "Fee config not found")
    for k, v in body.model_dump().items():
        setattr(cfg, k, v.upper() if isinstance(v, str)
                and k.endswith(("country", "currency")) else v)
    db.commit()
    db.refresh(cfg)
    return cfg


@router.delete("/fees/{config_id}", status_code=204)
def delete_fee_config(config_id: UUID, db: Session = Depends(get_db)):
    cfg = db.get(CorridorFeeConfig, config_id)
    if cfg is None:
        raise HTTPException(404, "Fee config not found")
    cfg.is_active = False  # soft-delete keeps quote audit trail intact
    db.commit()


@router.get("/stats/")
def stats(db: Session = Depends(get_db)):
    counts = dict(db.execute(
        select(Transaction.status, func.count()).group_by(Transaction.status)).all())
    return {
        "users": db.scalar(select(func.count()).select_from(User)),
        "transactions": db.scalar(select(func.count()).select_from(Transaction)),
        "by_status": {k.value if hasattr(k, "value") else k: v for k, v in counts.items()},
    }


@router.get("/transactions/")
def list_transactions(limit: int = 50, db: Session = Depends(get_db)):
    rows = db.execute(
        select(Transaction).order_by(Transaction.created_at.desc())
        .limit(min(limit, 200))).scalars()
    return [{
        "id": str(t.id), "voucher": t.voucher_code, "status": t.status.value,
        "send": f"{t.send_amount} {t.send_currency}",
        "payout": f"{t.payout_amount} {t.payout_currency}",
        "fee": f"{t.fee_amount} {t.send_currency}",
        "recipient": t.recipient_name, "created_at": t.created_at.isoformat(),
    } for t in rows]


# ---- dashboard page (unprotected static shell) ---------------------------------
pages = APIRouter(tags=["admin"])

_DASHBOARD_HTML = (Path(__file__).resolve().parents[2]
                   / "static" / "admin_dashboard.html")


@pages.get("/admin/dashboard/", response_class=HTMLResponse)
def dashboard():
    return HTMLResponse(_DASHBOARD_HTML.read_text(encoding="utf-8"))
