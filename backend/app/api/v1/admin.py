"""Admin CRUD for corridor fee configs. Protect with an admin dependency in prod."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_admin
from app.models import CorridorFeeConfig
from app.schemas import FeeConfigIn, FeeConfigOut

router = APIRouter(prefix="/admin", tags=["admin"],
                   dependencies=[Depends(require_admin)])


@router.post("/fees/", response_model=FeeConfigOut, status_code=201)
def create_fee_config(body: FeeConfigIn, db: Session = Depends(get_db)):
    cfg = CorridorFeeConfig(**{k: (v.upper() if isinstance(v, str) and k.endswith(("country", "currency")) else v)
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
        setattr(cfg, k, v.upper() if isinstance(v, str) and k.endswith(("country", "currency")) else v)
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
