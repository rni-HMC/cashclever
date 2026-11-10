"""Calls POST /v1/ping a few times against a fresh DB, so there's something real to
look at immediately after scripts/init_db.py. Delete once a real domain seeder
replaces it -- this exists only to demonstrate the TestClient-against-a-real-session
pattern real seed scripts should follow.

Run after scripts/init_db.py:
    DATABASE_URL=... python scripts/seed_demo.py
"""
from fastapi.testclient import TestClient

from app import models
from app.db import Base, SessionLocal, engine, get_db
from app.main import app


def main() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)

    for _ in range(3):
        resp = client.post("/v1/ping")
        resp.raise_for_status()

    total = db.query(models.PingLog).count()
    db.close()
    app.dependency_overrides.clear()

    print(f"Seeded: {total} ping_log row(s). GET/POST /v1/ping to see the count grow.")


if __name__ == "__main__":
    main()
