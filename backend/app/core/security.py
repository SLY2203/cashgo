"""FastAPI auth dependencies."""
import uuid

import jwt
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import User


def get_current_user(
    authorization: str = Header(...),
    db: Session = Depends(get_db),
) -> User:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Expected Bearer token")
    try:
        payload = jwt.decode(authorization.removeprefix("Bearer "),
                             settings.JWT_SECRET, algorithms=["HS256"])
        user = db.get(User, uuid.UUID(payload["sub"]))
    except (jwt.PyJWTError, ValueError, KeyError):
        user = None
    if user is None:
        raise HTTPException(401, "Invalid or expired token")
    return user


def require_admin(x_admin_key: str = Header(...)) -> None:
    """Static-key guard for admin routes — swap for RBAC in production."""
    if x_admin_key != settings.ADMIN_API_KEY:
        raise HTTPException(403, "Invalid admin key")
