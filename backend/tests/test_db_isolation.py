"""Regression coverage: the `db` fixture must isolate tests from each other even when
the code under test calls db.commit() (every router endpoint does). Named so it sorts
alphabetically near the front -- if this regresses, later tests seeing polluted data
should be easier to trace back here rather than discovered as confusing failures deep
in an unrelated test file."""
from app import models


def test_a_commits_a_ping(db):
    db.add(models.PingLog())
    db.commit()
    assert db.query(models.PingLog).count() == 1


def test_b_sees_no_pings_from_the_previous_test(db):
    """If the db fixture's SAVEPOINT isolation regressed to a bare rollback-only
    transaction, test_a's commit() above would have ended the outer transaction early
    and this would see count() == 1, not 0."""
    assert db.query(models.PingLog).count() == 0
    db.add(models.PingLog())
    db.commit()
    assert db.query(models.PingLog).count() == 1


def test_c_still_sees_no_pings(db):
    assert db.query(models.PingLog).count() == 0
