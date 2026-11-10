"""Drops and recreates all tables from app.models. Destructive -- wipes all data.
For resetting a dev/demo database to a clean slate. Never run against a database
holding real data you need to keep."""
from app.db import Base, engine
from app import models  # noqa: F401  -- import registers all models on Base.metadata

if __name__ == "__main__":
    confirm = input(
        f"This will DROP ALL TABLES (and all data) on {engine.url!r}. Type 'yes' to continue: "
    )
    if confirm != "yes":
        print("Aborted.")
    else:
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        print("Database reset.")
