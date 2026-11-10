"""Creates all tables from app.models. No Alembic for this cashclever -- deliberately
skipped to keep it lean; add real migrations once there's production data worth
preserving across schema changes."""
from app.db import Base, engine
from app import models  # noqa: F401  -- import registers all models on Base.metadata

if __name__ == "__main__":
    Base.metadata.create_all(bind=engine)
    print("Tables created.")
