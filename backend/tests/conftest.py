"""Shared test fixtures. Per-test transaction + rollback against a real Postgres
database (not SQLite -- the schema uses Postgres-specific UUID types).

join_transaction_mode="create_savepoint" is explicit rather than relying on
SQLAlchemy's default, since every router-endpoint test calls db.commit() (that's how
the endpoints work) -- without SAVEPOINT-based isolation, a commit() would end the
outer per-test transaction early and leak writes into later tests. See
tests/test_db_isolation.py for the regression test that would catch this.
"""
import os

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db import Base, get_db
from app.main import app

TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+psycopg://cashclever:cashclever@localhost:55432/cashclever"
)


@pytest.fixture(scope="session")
def engine():
    eng = create_engine(TEST_DB_URL)
    Base.metadata.create_all(bind=eng)
    yield eng
    Base.metadata.drop_all(bind=eng)


@pytest.fixture()
def db(engine):
    connection = engine.connect()
    connection.begin()
    Session = sessionmaker(bind=connection, join_transaction_mode="create_savepoint")
    session = Session()
    yield session
    session.close()
    # connection.close() discards the outer transaction -- including everything any
    # commit() during the test released into it via the SAVEPOINT mechanism above.
    connection.close()


@pytest.fixture()
def client(db):
    from fastapi.testclient import TestClient

    app.dependency_overrides[get_db] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()
