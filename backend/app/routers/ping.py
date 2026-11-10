from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app import generated_models, models
from app.db import get_db

router = APIRouter(prefix="/v1/ping", tags=["ping"])


@router.post("", response_model=generated_models.PingOut, operation_id="ping")
def ping(db: Session = Depends(get_db)):
    entry = models.PingLog()
    db.add(entry)
    db.commit()
    db.refresh(entry)

    count = db.query(func.count(models.PingLog.id)).scalar()
    return generated_models.PingOut(
        id=entry.id, message="pong", count=count, created_at=entry.created_at
    )
