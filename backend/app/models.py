"""Dummy SQLAlchemy model, one per row inserted by POST /v1/ping. Delete this once a
real domain model replaces it -- it exists only to prove the DB layer is wired."""
import uuid
from datetime import datetime

from sqlalchemy import DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class PingLog(Base):
    __tablename__ = "ping_log"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
